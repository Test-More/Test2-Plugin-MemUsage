use strict;
use warnings;
use Test2::V0;

# This test exercises Test2::Plugin::MemUsage::_collect_win32, which is the
# adapter between our module and Win32::Process::Memory. We do not need a
# real Windows host (or a real Win32::Process::Memory install) to verify
# our byte-to-kB conversion and field mapping; we just need a callable
# Win32::Process::Memory::GetProcessMemoryInfo that returns a known hash.
#
# If Win32::Process::Memory is installed for real, %INC is already set and
# our fake will simply overwrite the GetProcessMemoryInfo glob for the
# duration of this test. If it is not installed, we pretend it is so that
# require() inside the adapter returns true.

BEGIN {
    $INC{'Win32/Process/Memory.pm'} ||= __FILE__;
}

use Test2::Plugin::MemUsage;

{
    no warnings 'redefine', 'once';
    *Win32::Process::Memory::GetProcessMemoryInfo = sub {
        return {
            WorkingSetSize     => 1048576,    # 1024 kB
            PeakWorkingSetSize => 2097152,    # 2048 kB
            PagefileUsage      => 3145728,    # 3072 kB
        };
    };
}

subtest happy_path => sub {
    my %mem = Test2::Plugin::MemUsage::_collect_win32();
    is($mem{rss},  [1024, 'kB'], "rss converted from bytes");
    is($mem{peak}, [2048, 'kB'], "peak converted from bytes");
    is($mem{size}, [3072, 'kB'], "size converted from bytes");
};

subtest no_info_returned => sub {
    no warnings 'redefine';
    local *Win32::Process::Memory::GetProcessMemoryInfo = sub { undef };
    my @out = Test2::Plugin::MemUsage::_collect_win32();
    is(\@out, [], "GetProcessMemoryInfo undef -> empty");
};

subtest die_in_call => sub {
    no warnings 'redefine';
    local *Win32::Process::Memory::GetProcessMemoryInfo = sub { die "kaboom" };
    my @out = Test2::Plugin::MemUsage::_collect_win32();
    is(\@out, [], "exception inside call -> empty");
};

subtest partial_info => sub {
    no warnings 'redefine';
    local *Win32::Process::Memory::GetProcessMemoryInfo = sub {
        return {WorkingSetSize => 4096};    # only rss
    };
    my %mem = Test2::Plugin::MemUsage::_collect_win32();
    is($mem{rss},  [4, 'kB'],  "rss converted");
    is($mem{peak}, ['NA', ''], "peak NA when missing");
    is($mem{size}, ['NA', ''], "size NA when missing");
};

done_testing;
