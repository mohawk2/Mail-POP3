package Mail::POP3::Folder::virtual::jobserve;

my $FSTART = q(<tr><td[^>]*>(?:<b>)?<font\s+class='Normal'\s+face='arial'\s+Size='?2'?><b>); # one_parse
my $FEND = q(</b></font></td><td[^>]*>(?:&nbsp;)?</td><td[^>]*><font\s+class='Normal'\s+face='arial'\s+Size='?2'?>(.*?)</font></td></tr>); # one_parse
my $formno = 0; # form_fill
# this is at top so $DEBUG in L::UA::RNOk is correct one!
my $DEBUG = 0; # form_fill, redirect_cookie_loop et al
my $req_count = 0; # redirect_cookie_loop et al
my $UIDL_SUFFIX = '@jobby.jobserve.com';
require Data::Dumper if $DEBUG; # form_fill

use strict;
use POSIX qw(strftime); # _format_job
use CGI; # url_encode, list_parse, one_parse, parse_el, url_decode
use HTML::Form; # form_fill
use URI::URL; # redirect_cookie_loop et al
use HTTP::Request::Common; # redirect_cookie_loop et al
use HTTP::Cookies; # redirect_cookie_loop et al
{
    # redirect_cookie_loop et al
    package LWP::UserAgent::RedirectNotOk;
    use base qw(LWP::UserAgent);
    sub redirect_ok { print "Redirecting...\n" if $DEBUG; 0 }
}

my $CRLF = "\015\012";
my $MESSAGE_SIZE = 1000; # size of each virtual message

sub new {
    my (
        $class,
        $user_name,
        $password,
        $starturl, # from the config file
        $typefield,
        $withinfield,
        $sortfield,
        $queryfield,
    ) = @_;
    my $self = {};
    bless $self, $class;
    $user_name =~ s#\+# #g; # no spaces allowed in POP3, so "+" instead
    @$self{ qw(TYPE WITHIN SORT QUERY) } = split /:/, $user_name;
    $self->{STARTURL} = $starturl;
    $self->{TYPEFIELD} = $typefield;
    $self->{WITHINFIELD} = $withinfield;
    $self->{SORTFIELD} = $sortfield;
    $self->{QUERYFIELD} = $queryfield;
    $self->{MESSAGECNT} = 0;
    $self->{MSG2OCTETS} = {};
    $self->{MSG2UIDL} = {};
    $self->{MSG2URL} = {};
    $self->{MSG2JOBDATA} = {};
    $self->{TOTALOCTETS} = 0;
    $self->{DELETE} = {};
    $self->{DELMESSAGECNT} = 0;
    $self->{DELTOTALOCTETS} = 0;
    $self->{CJAR} = HTTP::Cookies->new;
    $self->{LIST_LOADED} = 0;
    $self;
}

sub lock_acquire {
    my $self = shift;
    1;
}

sub is_valid {
    my ($self, $msg) = @_;
    $self->_list_messages unless $self->{LIST_LOADED};
    $msg > 0 and $msg <= $self->{MESSAGECNT} and !$self->is_deleted($msg);
}

sub lock_release {
    my $self = shift;
    1;
}

sub uidl_list {
    my ($self, $output_fh) = @_;
    $self->_list_messages unless $self->{LIST_LOADED};
    for (1..$self->{MESSAGECNT}) {
        if (!$self->is_deleted($_)) {
            $output_fh->print("$_ $self->{MSG2UIDL}->{$_}$CRLF");
        }
    }
    $output_fh->print(".$CRLF");
}

# find relevant info about available messages
sub _list_messages {
    my $self = shift;
    my ($list_html, $list_url) = get_fill_submit(
        $self->{CJAR},
        $self->{STARTURL},
        {
            $self->{TYPEFIELD} => $self->{TYPE},
            $self->{WITHINFIELD} => $self->{WITHIN},
            $self->{SORTFIELD} => $self->{SORT},
            $self->{QUERYFIELD} => $self->{QUERY},
        },
    );
    my $list_data = list_parse($list_html);
    $list_data->{nextlink} = abs_with($list_data->{nextlink}, $list_url);
    my @jobs;
    while (1) {
        map { $_->{url} = abs_with($_->{url}, $list_url) } @{ $list_data->{jobs} };
        push @jobs, @{ $list_data->{jobs} };
        last if $list_data->{pageno} >= $list_data->{num_pages};
#last if $list_data->{pageno} >= 1;
        ($list_html, $list_url) = redirect_cookie_loop(
            $self->{CJAR}, GET($list_data->{nextlink}), 
        );
        $list_data = list_parse($list_html);
        $list_data->{nextlink} = abs_with($list_data->{nextlink}, $list_url)
            if $list_data->{nextlink};
    }
    my $cnt = 0;
    for my $job (@jobs) {
        $cnt++;
        my $octets = $MESSAGE_SIZE;
        $self->{MSG2OCTETS}->{$cnt} = $octets;
        $self->{MSG2UIDL}->{$cnt} = $job->{id} . $UIDL_SUFFIX;
        $self->{MSG2URL}->{$cnt} = $job->{url};
        $self->{TOTALOCTETS} += $octets;
    }
    $self->{MESSAGECNT} = $cnt;
    $self->{LIST_LOADED} = 1;
}

sub _get_joblines {
    my ($self, $message) = @_;
    my $data = $self->{MSG2JOBDATA}->{$message} || $self->_get_jobdata(
        $self->{MSG2URL}->{$message},
    );
    my $text = _format_job($data, $self->{MSG2UIDL}->{$message}, $self->{MSG2URL}->{$message});
    $text .= (' ' x ($MESSAGE_SIZE - length($text) - 1)) . "\n";
    split /\r*\n/, $text;
}

sub _get_jobdata {
    my ($self, $url) = @_;
    my $request = GET($url);
    my ($one_html, $one_url) = redirect_cookie_loop($self->{CJAR}, $request);
#warn "get $url = $one_url:\n$one_html\n\n";
#my $one_html = '';
    one_parse($one_html);
}

sub _format_job {
    my ($jobdata, $message_id, $url) = @_;
    my ($mday, $mon, $year, $hour, $min, $sec) = split /[\/\s:]/, $jobdata->{posted};
    my @tm = ($sec, $min, $hour, $mday, $mon, $year - 1900);
    my $date = strftime "%a, %d %b %Y %H:%M:%S GMT (GMT)", @tm;
    <<EOF;
Received: from jobserve.com by mpopd for user; $date
From: $jobdata->{email}
Subject: Jobserve reference $jobdata->{reference}
Date: $date
Message-ID: $message_id

$jobdata->{type}: $jobdata->{title}
$jobdata->{description}

Location: $jobdata->{location}
Start Date: $jobdata->{start}
Duration: $jobdata->{duration}
Salary/Rate: $jobdata->{money}
Agency: $jobdata->{agency}
Contact: $jobdata->{contact}
Telephone: $jobdata->{telephone}
Fax: $jobdata->{fax}
E-Mail: $jobdata->{email}
Reference: $jobdata->{reference}
Posted Date: $jobdata->{posted}

Data from: $url
EOF
}

# $message starts at 1
sub retrieve {
    my ($self, $message, $output_fh, $mbox_destined) = @_;
    $self->_list_messages unless $self->{LIST_LOADED};
    for ($self->_get_joblines($message)) {
        # byte-stuff lines starting with .
        s/^\./\.\./o unless $mbox_destined;
        my $line = $mbox_destined ? "$_\n" : "$_$CRLF";
        $output_fh->print($line);
    }
    close MSG;
}

# $message starts at 1
# returns number of bytes
sub top {
    my ($self, $message, $output_fh, $body_lines) = @_;
    $self->_list_messages unless $self->{LIST_LOADED};
    my $top_bytes = 0;
    my @lines = $self->_get_joblines($message);
    my $linecount = 0;
    # print the headers
    while ($linecount < @lines) {
        $_ = $lines[$linecount++];
        my $out = "$_$CRLF";
        $output_fh->print($out);
        $top_bytes += length($out);
        last if /^\s+$/;
    }
    my $cnt = 0;
    # print the TOP arg number of body lines
    while ($linecount < @lines) {
        $_ = $lines[$linecount++];
        ++$cnt;
        last if $cnt > $body_lines;
        # byte-stuff lines starting with .
        s/^\./\.\./o;
        my $out = "$_$CRLF";
        $output_fh->print($out);
        $top_bytes += length($out);
    }
    close MSG;
    $output_fh->print(".$CRLF");
    $top_bytes;
}

sub is_deleted {
    my ($self, $message) = @_;
    return $self->{DELETE}->{$message};
}

sub delete {
    my ($self, $message) = @_;
    $self->{DELETE}->{$message} = 1;
    $self->{DELMESSAGECNT} += 1;
    $self->{DELTOTALOCTETS} += $self->{OCTETS}->{$message};
}

sub flush_delete {
    my $self = shift;
return;
    for (1..$self->{MESSAGECNT}) {
        if ($self->{MAILBOX}->is_deleted($_)) {
            unlink $self->_msg2filename($_);
        }
    }
}

sub reset {
    my $self = shift;
    $self->{DELETE} = {};
    $self->{DELMESSAGECNT} = 0;
    $self->{DELTOTALOCTETS} = 0;
}

sub octets {
    my ($self, $message) = @_;
    $self->_list_messages unless $self->{LIST_LOADED};
    if (defined $message) {
        $self->{MSG2OCTETS}->{$message};
    } else {
        $self->{TOTALOCTETS} - $self->{DELTOTALOCTETS};
    }
}

sub messages {
    my ($self) = @_;
    $self->_list_messages unless $self->{LIST_LOADED};
    $self->{MESSAGECNT} - $self->{DELMESSAGECNT};
}

sub uidl {
    my ($self, $message) = @_;
    $self->_list_messages unless $self->{LIST_LOADED};
    $self->{MSG2UIDL}->{$message};
}

sub url_encode {
    my $hash = shift;
    my $args = $hash->{cgi_args};
    join '?', $hash->{link_to}, join '&', map {
        join '=', map { CGI::escape($_) } $_, $args->{$_}
    } keys %$args;
}

sub get_fill_submit {
    my ($cjar, $url, $vars, $varnamechange) = @_;
    my ($html, $real_url) = redirect_cookie_loop($cjar, GET($url));
    parse_fill_submit($cjar, $html, $real_url, $vars, $varnamechange);
}

sub parse_fill_submit {
    my ($cjar, $html, $real_url, $vars, $varnamechange) = @_;
    my $form = HTML::Form->parse($html, $real_url);
    {
        local $^W = 0; # don't want to hear about "readonly"
        map {
            $form->value($_, $vars->{$_});
        } keys %$vars;
    }
    $formno++;
    to_file("f$formno.wri", Data::Dumper::Dumper($varnamechange, $form)) if $DEBUG;
    map {
        my $input = $form->find_input(undef, undef, $_);
        $input->name($varnamechange->{$_});
        local $^W = 0; # don't want to hear about "readonly"
        $input->value('') unless defined $input->value;
    } keys %$varnamechange
        if $varnamechange;
    to_file("f$formno-after.wri", Data::Dumper::Dumper($varnamechange, $form)) if $DEBUG;
    my $form_html;
    ($form_html, $real_url) = redirect_cookie_loop(
        $cjar,
        $form->click,
    );
    ($form_html, $real_url);
}

sub list_parse {
    my $text = shift;
    my ($searchxml) = $text =~ m#
        (<input\s+name='JobIDXML'.*?>)
    #six;
    $searchxml = parse_el($searchxml)->{attr}->{value};
    my @jobids = $searchxml =~ m#
        <job><jobid>(.*?)</jobid></job>
    #gix;
    my @jobs = map { +{ id => $_, url => "JobDetail.asp?jobid=$_", } } @jobids;
    my ($pageno) = $searchxml =~ m#
        <pagenumber>(.*?)</pagenumber>
    #gix;
    my ($num_pages) = $searchxml =~ m#
        <pagecount>(.*?)</pagecount>
    #gix;
    my ($nextlink) = $text =~ m#
        (<a[^>]+class='ToolBar'.*?>Next\s+Page[^<>]*</a>)
    #six;
    $nextlink = parse_el($nextlink)->{attr}->{href};
    +{
        jobs => \@jobs,
        pageno => $pageno,
        num_pages => $num_pages,
        nextlink => $nextlink,
    };
}

sub _salami_parse {
    my ($text, @patterns) = @_;
    my @results;
    while (my $pattern = shift @patterns) {
#warn "start: ", length($text), ":\n'$pattern'\n'$text'\n";
        $text =~ s#.*?$pattern##si;
#warn "now: ", length($text), ": $1\n\n\n";
        push @results, CGI::unescapeHTML($1);
    }
    @results;
}

sub one_parse {
    my $text = shift;
    $text =~ s#.*<font[^>]+class='title'[^>]*>job(?:\s|&nbsp;)+detail##si;
    my (
        $title,
        $type,
        $description,
        $location,
        $start,
        $duration,
        $money,
        $agency,
        $contact,
        $telephone,
        $fax,
        $email,
        $reference,
        $posted,
    ) = _salami_parse(
        $text,
        (q(<font\s+class='Normal'[^>]+size='?2'?><b>(.*?)</b></font>)) x 2,
        q(<font\s+class='Normal'[^>]+size='?2'?>(.*?)</font>),
        (map { qq($FSTART$_$FEND) } (
            'Location',
            'Start Date',
            'Duration',
            'Salary/Rate',
            'Agency',
            'Contact',
            'Telephone',
            'Fax',
        )),
        q(<td[^>]*><font\s+class='Normal'[^>]+size='?2'?><a[^>]*?>([^<>]*?)</a>[^<>]*</font></td></tr>),
        (map { qq($FSTART$_$FEND) } (
            'Reference',
            'Posted Date',
        )),
    );
    +{
        title => $title,
        type => $type,
        description => $description,
        location => $location,
        start => $start,
        duration => $duration,
        money => $money,
        agency => $agency,
        contact => $contact,
        telephone => $telephone,
        fax => $fax,
        email => $email,
        reference => $reference,
        posted => $posted,
    };
}

# assumes only one of each attribute! also assumes no invalid stuff
sub parse_el {
    my $text = shift;
    $text =~ s/^<//;
    $text =~ s/>$//;
    $text =~ s#^(\S+)##;
    my $descrip = { el => lc($1), attr => {} };
    while ($text =~ /\S/) {
        $text =~ s#^\s+##;
        $text =~ s#([^\s=]+)(=?)(['"]?)##;
        my $name = lc $1;
        my $value = undef;
        if ($2) {
            # equals sign - has some value
            if ($3) {
                $text =~ s#(.*?)$3##s;
                $value = $1; # $1 is now lexically scoped!
            } else {
                $text =~ s#(\S*)##;
                $value = $1; # $1 is now lexically scoped!
            }
        }
        $descrip->{attr}->{$name} = CGI::unescapeHTML($value);
    }
    $descrip;
}

sub strip_markup {
    my $text = shift;
    $text =~ s#<.*?>##g;
    $text;
}

sub url_decode {
    my $text = shift;
    my ($link_to, $cgi_args) = split /\?/, $text, 2;
    if ($cgi_args) {
        $cgi_args = {
            map {
                map { CGI::unescape($_) } split /=/, $_, 2
            } split /[&;]/, $cgi_args
        };
    }
    +{
        link_to => $link_to,
        cgi_args => $cgi_args,
    };
}

# modify input $cjar, return also a $response
sub redirect_cookie_loop {
    my ($cjar, $request) = @_;
    # otherwise cookies set during redirects get lost...
    my $ua = LWP::UserAgent::RedirectNotOk->new;
#$ua->proxy('http', 'http://localhost:3128');
    $ua->agent('Mozilla/4.0 (compatible; MSIE 5.5; Windows NT 5.0)');
    my $response;
    while (1) {
        $req_count++;
        $cjar->add_cookie_header($request);
        print "req $req_count: ", $request->uri, "\n" if $DEBUG;
        to_file("r${req_count}req.wri", $request->as_string) if $DEBUG;
        $response = $ua->request($request);
        to_file("r${req_count}resp.wri", $response->as_string) if $DEBUG;
        unless ($response->is_success or $response->is_redirect) {
            my $text = $response->error_as_HTML;
            $text =~ s/<.*?>//g;
            $text =~ s/\s+$//;
            die "Failed web request: $text\n";
        }
        $cjar->extract_cookies($response);
        my $new_loc;
        if ($response->is_redirect) {
#print "302\n";
            $new_loc = $response->header('location');
        } elsif ($response->header('refresh')) {
#print "refresh\n";
            $new_loc = parse_refresh($response->header('refresh'));
        } else {
            last;
        }
#use Data::Dumper; print Dumper($response);
#print "new_loc: $new_loc\n";
        $request = GET abs_with($new_loc, $request->uri);
    }
    ($response->content, $response->request->uri->as_string);
}

sub parse_refresh {
    my $header_val = shift;
    my ($url) = $header_val =~ m#url="?([^"\s]*)#i;
    # kludge alert!
    my $hash = url_decode($url);
    if ($hash->{cgi_args}->{js}) {
        delete $hash->{cgi_args}->{js};
        $hash->{cgi_args}->{utf8} = 1;
        url_encode($hash);
    } else {
        $url;
    }
}

sub abs_with {
    my ($url, $against) = @_;
    URI::URL->new($url, $against)->abs->as_string;
}

1;

__END__

=head1 NAME

Mail::POP3::Folder::virtual::jobserve - class that makes Jobserve look like a POP3 mailbox

=head1 DESCRIPTION

This class makes Jobserve look like a POP3 mailbox in accordance with the
requirements of a POP3 server. It is entirely API-compatible with
L<Mail::POP3::Folder::mbox>.

The username is interpreted as a ":"-separated string, also "URL-encoded" such that spaces are encoded as "+" characters. The information contained in the POP3 username is four items:

=over 5

=item Job Type

Either C<P> (permanent), C<C> (contract) or C<*> (either).

=item Posted within (in days)

1-5.

=item Sort hits by

Either C<Rank> or C<DateTime>, being either the matching score or most recent first.

=item User-specified query

See Jobserve website, http://www.jobserve.com/, for possibilities.

=back

Only IT jobs are currently searched for. The virtual e-mails will be exactly 1000 octets long, being either padded or truncated (unlikely) to this length.

#  each virtual message is 1000 octets and will be padded thus by format function

=head1 METHODS

None extra are defined.

=head1 SEE ALSO

RFC 1939, L<Mail::POP3::Folder::mbox>.
