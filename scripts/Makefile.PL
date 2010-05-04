use ExtUtils::MakeMaker qw(WriteMakefile);

# must make sure mpopd.conf gets backed up by install!
# must make sure mpopd_trusted and mpopd-allow_deny get preserved by install!

#--- Make the Makefile.
WriteMakefile(
        NAME => 'Mail::POP3-scripts',
        EXE_FILES => [qw(
            installscript mpopd mpopdctl mpopdstats
        )],
);
