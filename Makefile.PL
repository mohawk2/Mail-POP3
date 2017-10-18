use ExtUtils::MakeMaker;

# must make sure mpopd.conf gets backed up by install!
# must make sure mpopd_trusted and mpopd-allow_deny get preserved by install!

#--- Make the Makefile.
WriteMakefile(
  NAME => 'Mail::POP3',
  VERSION_FROM => 'lib/Mail/POP3.pm',
  PREREQ_PM => {
    'HTTP::Cookies' => 0,
    'HTML::Form' => 0,
    'Email::MIME' => 0,
    'HTML::FormatText' => 0,
  },
  DIR => [qw(scripts)],
  META_MERGE => {
    "meta-spec" => { version => 2 },
    dynamic_config => 0,
    resources => {
      repository => {
        type => 'git',
        url => 'git@github.com:mohawk2/Mail-POP3.git',
        web => 'https://github.com/mohawk2/Mail-POP3',
      },
      bugtracker  => {
        web => 'https://github.com/mohawk2/Mail-POP3/issues',
      },
      license => [ 'http://dev.perl.org/licenses/' ],
    },
    prereqs => {
      develop => {
        requires => {
          'Pod::Markdown' => 0,
        },
      },
    },
  },
);

sub MY::postamble {
  <<EOF;
pure_all :: README.md

README.md : lib/Mail/POP3.pm
\tpod2markdown \$< >\$\@
EOF
}
