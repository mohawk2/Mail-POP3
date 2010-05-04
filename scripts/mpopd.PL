#!/usr/bin/perl

use Config;

open OUTPUT, ">$ARGV[0]" or die "$ARGV[0]: $!\n";
select OUTPUT;

print << "!GROK!THIS!";
$Config{'startperl'}
!GROK!THIS!
print << '!GROK!THIS!';

use strict;
use Mail::POP3;
use POSIX qw(setsid);
use Getopt::Long;

my $USAGE = "Usage: $0 -v | [-s] config-file [portnum]\n";
my $singlethread;

GetOptions(
    v => sub { print "mpopd V$Mail::POP3::VERSION\n"; exit(0); },
    s => \$singlethread,
);

my ($config_file, $portnum) = @ARGV;
die $USAGE unless -f $config_file;
die $USAGE if defined $portnum and $portnum == 0; # ie non-numeric

my $config_text = Mail::POP3->from_file($config_file);
my $config = Mail::POP3->read_config($config_text);
Mail::POP3->make_sane($config);

# Accept a port to bind to, for special purposes
if (defined $portnum) {
    $config->{port} = $portnum;
}

if ($singlethread) {
    my $server_sock = IO::Socket::INET->new(
        Listen    => 1,
        LocalPort => $config->{port},
        Proto     => 'tcp',
    );
    while (my $sock = $server_sock->accept) {
        my $server = Mail::POP3::Server->new(
            $config,
        );
        $server->start(
            $sock,
            $sock,
            $sock->peerhost,
        );
    }
} elsif (my $paddr = getpeername STDIN) {
    # we are being called by inetd
    my ($port, $iaddr) = sockaddr_in($paddr);
    my $server = Mail::POP3::Server->new(
        $config,
    );
    $server->start(
        \*STDIN,
        \*STDOUT,
        inet_ntoa($iaddr),
    );
} else {
    # completely detach from any controlling service/terminal
    eval { setsid(); };
    # Start the POP3 server parent daemon
    my $daemon = Mail::POP3::Daemon->new(
        $config,
    );
    $daemon->start;
}
!GROK!THIS!
