use 5.010000;
use ExtUtils::MakeMaker 6.55_01;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'querypkg',
    ABSTRACT          => 'Tool query packages using packages.sabayon.org',
    VERSION           => 2.100,
    BUILD_REQUIRES    => {
        'Test::More'      => 0
	},
    PREREQ_PM         => {
        'Term::ANSIColor' => 0,
        'Carp'            => 0,
        'LWP::UserAgent'  => 0,
        'URI::Escape'     => 0,
        'JSON::XS'        => 0
    },
    EXE_FILES         => [ 'bin/querypkg', 'bin/download_entropy_packages.sh' ],
    LICENSE           => 'mit',
);
