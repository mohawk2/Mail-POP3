use strict;
use Test::More tests => 3;

our %CONFIG;
do 't/testcommon.pl';

use File::Temp;

END {ok(0, 'loaded') unless $::loaded;}
use Mail::POP3;
$::loaded = 1;
ok(1, 'loaded');

my $fake_mbox = File::Temp->new;
print $fake_mbox $CONFIG{fake_mbox_text};
$fake_mbox->seek(0, Fcntl::SEEK_SET);
my $tmpdir = File::Temp->newdir;
my $config = Mail::POP3->read_config($CONFIG{config_text});
$config->{mailbox_args} = sub {
  (
    $<,
    $(,
    $fake_mbox,
    '^From ',
    '^\\s*$',
    $tmpdir,
    0, # debug
  );
};
ok(1, 'config read');

print $fake_mbox $CONFIG{fake_mbox_text};
my $tmpfh = File::Temp->new;
$tmpfh->print(<<EOF);
USER bob
PASS bob1
UIDL
TOP 3 2
RETR 3
DELE 2
UIDL
QUIT
EOF
my $receivedheader = "Received: from fredo.co.uk\n    by mpopd V$Mail::POP3::VERSION";
my $msg3receivednofrom = "$receivedheader\n$CONFIG{msg3nofrom}";
my $msg3receivednofromCRLF = $msg3receivednofrom;
$msg3receivednofromCRLF =~ s#\n#\015\012#g;
my $msg3length = length($msg3receivednofromCRLF) + 43; # 43 = length " for bob"
my $pop3_ref = <<EOF;
+OK mpopd V3.x
+OK bob send me your password
+OK thanks bob...
+OK unique-id listing follows
1 <$CONFIG{msgid1}>
2 <$CONFIG{msgid2}>
3 <$CONFIG{msgid3}>
.
+OK top of message 3 follows
$receivedheader
$CONFIG{msg3topnofrom}.
+OK $msg3length octets
$msg3receivednofrom.
+OK message 2 flagged for deletion
+OK unique-id listing follows
1 <$CONFIG{msgid1}>
3 <$CONFIG{msgid3}>
.
+OK TTFN bob...
EOF
$tmpfh->seek(0, Fcntl::SEEK_SET);
my $server = Mail::POP3::Server->new($config);
my $tmpfh2 = File::Temp->new;
if (my $kid = fork) {
  waitpid $kid, 0;
} else {
  $server->start($tmpfh, $tmpfh2, '127.0.0.1');
  exit;
}
$tmpfh2->seek(0, Fcntl::SEEK_SET);
my $pop3 = join '', <$tmpfh2>;
$pop3 =~ s#^\s*for bob.*?\r\n##gm;
$pop3_ref =~ s#\n#\015\012#g;
#print Data::Dumper::Dumper($pop3, $pop3_ref);
ok($pop3 eq $pop3_ref, 'talk pop3 to server');

undef $tmpdir;
