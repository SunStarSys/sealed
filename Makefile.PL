use ExtUtils::MakeMaker;

WriteMakefile(
	NAME => "sealed",
	VERSION_FROM => "lib/sealed.pm",
        ABSTRACT_FROM => "lib/sealed.pm",
	PREREQ_PM => {
	  'B::Generate' => 0,
	},
	test => { TESTS => "signature.pl bench.pl" },
	SIGN => 1,
);
