use ExtUtils::MakeMaker qw(prompt WriteMakefile);

# must make sure mpopd.conf gets backed up by install!
# must make sure mpopd_trusted and mpopd-allow_deny get preserved by install!

#--- Make the Makefile.
WriteMakefile(
        'NAME' => 'Mail::POP3',
        'DISTNAME' => "Mail-POP3",
        'VERSION_FROM' => 'lib/Mail/POP3.pm',
	PREREQ_PM => {
	    'HTML::Form' => 0,
	    'Email::Stuffer' => 0,
	    'HTML::FormatText' => 0,
	},
        'dist' => {
                COMPRESS => "gzip -9f",
                SUFFIX => "gz",
        },
        DIR => [qw(scripts)],
#        PMLIBDIRS => [qw(lib)],
);

sub to_file {
    my ($file, $data) = @_;
    local *FH;
    open FH, ">$file";
    print FH $data;
    close FH;
}

sub prompt_chomp {
    my ($prompt, $default) = @_;
    chomp $prompt;
    prompt($prompt, $default);
}

sub prompt_chomp_file {
    my ($prompt, $file, $default) = @_;
    $default = from_file($file) if -f $file;
    my $reply = prompt_chomp($prompt, $default);
    to_file($file, $reply);
    $reply;
}

sub from_file {
    my $file = shift;
    local (*FH, $/);
    open FH, $file or die "$file: $!\n";
    <FH>;
}
