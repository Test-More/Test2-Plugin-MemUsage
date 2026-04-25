use strict;
use warnings;
use Test2::V0;

BEGIN {
    if ($^O eq 'MSWin32') {
        plan skip_all => "ps test requires a unix shell";
    }

    my $probe = qx{echo hello 2>/dev/null};
    unless (defined $probe && $probe =~ /hello/) {
        plan skip_all => "shell echo unavailable";
    }
}

use Test2::Plugin::MemUsage;

subtest happy_path => sub {
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::ps_command = sub { q{echo '  1234  5678'} };
    my %mem = Test2::Plugin::MemUsage::_collect_ps();
    is($mem{rss},  ['1234', 'kB'], "rss");
    is($mem{size}, ['5678', 'kB'], "size");
    is($mem{peak}, ['NA', ''],     "peak NA (ps does not surface)");
};

subtest empty_output => sub {
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::ps_command = sub { 'true' };
    my @out = Test2::Plugin::MemUsage::_collect_ps();
    is(\@out, [], "empty output -> empty");
};

subtest unparseable_output => sub {
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::ps_command = sub { q{echo 'definitely not numbers'} };
    my @out = Test2::Plugin::MemUsage::_collect_ps();
    is(\@out, [], "unparseable -> empty");
};

subtest real_ps_if_present => sub {
    my $rss_vsz = qx{ps -o rss=,vsz= -p $$ 2>/dev/null};
    skip_all "real ps not usable on this host"
        unless defined $rss_vsz && $rss_vsz =~ /^\s*\d+\s+\d+\s*$/m;

    my %mem = Test2::Plugin::MemUsage::_collect_ps();
    like($mem{rss}->[0],  qr/^\d+$/, "rss numeric from real ps");
    like($mem{size}->[0], qr/^\d+$/, "size numeric from real ps");
    is($mem{rss}->[1],  'kB', "rss units kB");
    is($mem{size}->[1], 'kB', "size units kB");
};

done_testing;
