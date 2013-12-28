# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

use strict;
BEGIN { $| = 1; print "1..13\n"; }
END {print "not ok 1\n" unless $::loaded;}
use Mail::POP3;
$::loaded = 1;
print "ok 1\n";

######################### End of black magic.

require Data::Dumper;
$Data::Dumper::Indent = 1;
$Data::Dumper::Terse = 2;

my $fake_mbox = "/tmp/pop3.mbox.$$";
my $msgid1 = '200111132338.fADNc4727035@example.com';
my $msgid2 = '200111132338.fADNcNg27040@example.com';
my $msgid3 = '200111132338.fADNcna27048@example.com';
my $msg1from = "From user  Tue Nov 13 23:38:04 2001\n";
my $msg1nofrom = <<EOF;
Return-Path: <user\@example.com>
Received: (from user\@localhost)
        by host.example.com (8.11.2/8.11.2) id fADNc4727035
        for user; Tue, 13 Nov 2001 23:38:04 GMT
Date: Tue, 13 Nov 2001 23:38:04 GMT
From: User <user\@example.com>
Message-Id: <$msgid1>
To: user\@host.example.com
Subject: test

EOF
my $msg1 = $msg1from . $msg1nofrom;
my $msg2from = "From user  Tue Nov 13 23:38:23 2001\n";
my $msg2nofrom = <<EOF;
Return-Path: <user\@example.com>
Received: (from user\@localhost)
        by host.example.com (8.11.2/8.11.2) id fADNcNg27040
        for user; Tue, 13 Nov 2001 23:38:23 GMT
Date: Tue, 13 Nov 2001 23:38:23 GMT
From: User <user\@example.com>
Message-Id: <$msgid2>
To: user\@host.example.com
Subject: test2

EOF
my $msg2 = $msg2from . $msg2nofrom;
my $msg3from = "From user  Tue Nov 13 23:38:49 2001\n";
my $msg3topnofrom = <<EOF;
Return-Path: <user\@example.com>
Received: (from user\@localhost)
        by host.example.com (8.11.2/8.11.2) id fADNcna27048
        for user; Tue, 13 Nov 2001 23:38:49 GMT
Date: Tue, 13 Nov 2001 23:38:49 GMT
From: User <user\@example.com>
Message-Id: <$msgid3>
To: user\@host.example.com
Subject: test3

it's got a
longer
EOF
my $msg3bot = <<EOF;
body

EOF
my $msg3nofrom = $msg3topnofrom . $msg3bot;
my $msg3 = $msg3from . $msg3nofrom;
my $fake_mbox_text = join '', $msg1, $msg2, $msg3;
to_file($fake_mbox, $fake_mbox_text);
my $tmpdir = "/tmp/pop3.mbox.tmpdir.$$";
mkdir $tmpdir, 0700;
my $config_text = << "EOF";
{
  'port' => '6110',
  'max_servers' => 10,
  'mpopd_pid_file' => 'out/mpopd.pid',
  'mpopd_pam_service' => 'mpopx',
  'trusted_networks' => '/usr/local/mpopd/mpopd_trusted',
  'userlist' => '.userlist',
  'mpopd_failed_mail' => 'out/mpopd_failed_mail',
  'host_mail_path' => '/var/spool/popmail',
  'mpopd_spool' => 'out/mpopd_spool',
  'receivedfrom' => 'fredo.co.uk',
  'passsecret' => 1,
  'greeting' => 'mpopd V3.x',
  'addreceived' => {
    'bob' => 1
  },
  'user_log' => {
    'markjt' => 1
  },
  'message_start' => '^From ',
  'message_end' => '^\\s+\$',
  'mailgroup' => 12,
  'retry_on_lock' => 0,
  'mail_spool_dir' => '/var/spool/mail',
  'mpopd_conf_version' => '$Mail::POP3::VERSION',
  'debug' => 1,
  'hosts_allow_deny' => '/usr/local/mpopd/mpopd_allow_deny',
  'timezone' => 'GMT',
  'timeout' => 10,
  'user_log_dir' => 'out/mpopd_log',
  'debug_log' => 'out/mpopd.log.main',
  'reject_bogus_user' => 0,
  'allow_non_fqdn' => 0,
  'user_debug' => {
  },
  'connection_class' => 'Mail::POP3::Security::Connection',
  fork_alert => ">/usr/local/mpopd/fork_alert",
  user_check => sub { 1 },
  password_check => sub { 1 },
  mailbox_class => 'Mail::POP3::Folder::mbox::parse_to_disk',
}
EOF
my $config = Mail::POP3->read_config($config_text);
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
print "ok 2\n";

my $mailbox = Mail::POP3::Folder::mbox::parse_to_disk->new(
    'user',
    'password',
    $config->{mailbox_args}->(),
);
print "not " unless $mailbox->lock_acquire;
print "ok 3\n";

my $tmpfh = IO::File::new_tmpfile();
$mailbox->uidl_list($tmpfh);
$tmpfh->seek(0, Fcntl::SEEK_SET);
my $list = join '', <$tmpfh>;
my $list_ref = <<EOF;
1 <$msgid1>
2 <$msgid2>
3 <$msgid3>
.
EOF
$list_ref =~ s#\n#\015\012#g;
print "not "
    unless $list eq $list_ref and
    $mailbox->messages == 3 and
    $mailbox->octets == 1053;
print "ok 4\n";

print "not "
    unless $mailbox->uidl(2) eq "<$msgid2>";
print "ok 5\n";

$mailbox->delete(2);
$tmpfh = IO::File::new_tmpfile();
$mailbox->uidl_list($tmpfh);
$tmpfh->seek(0, Fcntl::SEEK_SET);
$list = join '', <$tmpfh>;
$list_ref = <<EOF;
1 <$msgid1>
3 <$msgid3>
.
EOF
$list_ref =~ s#\n#\015\012#g;
print "not "
    unless $list eq $list_ref and
    $mailbox->messages == 2 and
    $mailbox->octets == 711;
print "ok 6\n";

$tmpfh = IO::File::new_tmpfile();
$mailbox->top(3, $tmpfh, 2);
$tmpfh->seek(0, Fcntl::SEEK_SET);
my $top = join '', <$tmpfh>;
my $top_ref = $msg3topnofrom;
$top_ref =~ s#\n#\015\012#g;
print "not " unless $top eq $top_ref;
print "ok 7\n";

$tmpfh = IO::File::new_tmpfile();
$mailbox->retrieve(3, $tmpfh);
$tmpfh->seek(0, Fcntl::SEEK_SET);
my $retrieve = join '', <$tmpfh>;
my $retrieve_ref = $msg3nofrom;
$retrieve_ref =~ s#\n#\015\012#g;
print "not "
    unless $retrieve eq $retrieve_ref and
    $mailbox->octets(2) == 342;
print "ok 8\n";

print "not "
    unless !$mailbox->is_valid(2) and
    $mailbox->is_valid(3);
print "ok 9\n";

$mailbox->reset;
print "not "
    unless $mailbox->is_valid(2) and
    $mailbox->is_valid(3);
print "ok 10\n";
$mailbox->delete(2);

print "not "
    unless $mailbox->is_deleted(2) and
    !$mailbox->is_deleted(3);
print "ok 11\n";

$mailbox->flush_delete;
$mailbox->lock_release;
my $flush_ref = $msg1 . $msg3;
print "not "
    unless from_file($fake_mbox) eq $flush_ref;
print "ok 12\n";
unlink $fake_mbox;
rmdir $tmpdir;

mkdir $tmpdir, 0700;
to_file($fake_mbox, $fake_mbox_text);
$tmpfh = IO::File::new_tmpfile();
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
my $msg3receivednofrom = "$receivedheader\n$msg3nofrom";
my $msg3receivednofromCRLF = $msg3receivednofrom;
$msg3receivednofromCRLF =~ s#\n#\015\012#g;
my $msg3length = length($msg3receivednofromCRLF) + 43; # 43 = length " for bob"
my $pop3_ref = <<EOF;
+OK mpopd V3.x
+OK bob send me your password
+OK thanks bob...
+OK unique-id listing follows
1 <$msgid1>
2 <$msgid2>
3 <$msgid3>
.
+OK top of message 3 follows
$receivedheader
$msg3topnofrom.
+OK $msg3length octets
$msg3receivednofrom.
+OK message 2 flagged for deletion
+OK unique-id listing follows
1 <$msgid1>
3 <$msgid3>
.
+OK TTFN bob...
EOF
$tmpfh->seek(0, Fcntl::SEEK_SET);
my $server = Mail::POP3::Server->new($config);
my $tmpfh2 = IO::File::new_tmpfile();
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
print "not " unless $pop3 eq $pop3_ref;
print "ok 13\n";

unlink $fake_mbox or die "unlink $fake_mbox: $!\n";
rmdir $tmpdir or die "rmdir $tmpdir: $!\n";

sub from_file {
    my $file = shift;
    local (*FH, $/);
    open FH, $file or die "$file: $!\n";
    <FH>;
}

sub to_file {
    my ($file, $data) = @_;
    local *FH;
    open FH, ">$file" or die;
    print FH $data;
}
