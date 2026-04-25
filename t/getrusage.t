use strict;
use warnings;
use Test2::V0;

# Exercises Test2::Plugin::MemUsage::_maxrss_kb plus the collect_mem
# last-resort path. Like t/win32.t we fake the upstream module rather
# than require a real install, because what we want to test is our
# unit-conversion / dispatch logic, not BSD::Resource itself.

BEGIN {
    $INC{'BSD/Resource.pm'} ||= __FILE__;
}

{
    no warnings 'redefine', 'once';
    *BSD::Resource::RUSAGE_SELF = sub () { 0 };
    *BSD::Resource::getrusage   = sub { (0, 0, 8192) };  # ru_maxrss = index 2
}

use Test2::Plugin::MemUsage;

subtest linux_uses_kb_directly => sub {
    local $^O = 'linux';
    is(Test2::Plugin::MemUsage::_maxrss_kb(), 8192, "ru_maxrss returned as kB on Linux");
};

subtest darwin_converts_bytes => sub {
    local $^O = 'darwin';
    is(Test2::Plugin::MemUsage::_maxrss_kb(), 8, "ru_maxrss / 1024 on darwin");
};

subtest zero_maxrss_returns_undef => sub {
    no warnings 'redefine';
    local *BSD::Resource::getrusage = sub { (0, 0, 0) };
    is(Test2::Plugin::MemUsage::_maxrss_kb(), undef, "0 maxrss -> undef");
};

subtest empty_getrusage_returns_undef => sub {
    no warnings 'redefine';
    local *BSD::Resource::getrusage = sub { () };
    is(Test2::Plugin::MemUsage::_maxrss_kb(), undef, "empty list from getrusage -> undef");
};

subtest collect_mem_last_resort => sub {
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::_collector_for_os = sub { undef };
    local $^O = 'linux';

    my %mem = Test2::Plugin::MemUsage::collect_mem();
    is($mem{peak}, [8192, 'kB'], "fallback fills peak");
    is($mem{rss},  ['NA', ''],   "rss NA");
    is($mem{size}, ['NA', ''],   "size NA");
};

subtest augment_peak_uses_real_helper => sub {
    # Don't mock _maxrss_kb here - run the real one against our fake
    # BSD::Resource so the augment_peak -> _maxrss_kb -> getrusage
    # chain is exercised end to end.
    local $^O = 'linux';
    my %in = (
        rss  => ['100', 'kB'],
        size => ['200', 'kB'],
        peak => ['NA',  ''],
    );
    my %out = Test2::Plugin::MemUsage::_augment_peak(%in);
    is($out{peak}, [8192, 'kB'], "augment_peak filled peak from getrusage chain");
};

done_testing;
