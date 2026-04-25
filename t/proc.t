use strict;
use warnings;
use Test2::V0;
use File::Temp qw/tempfile/;

use Test2::Plugin::MemUsage;

subtest happy_path => sub {
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::proc_file = sub { 't/procfile' };
    my %mem = Test2::Plugin::MemUsage::_collect_proc();
    is($mem{peak}, ['25176', 'kB'], "peak");
    is($mem{size}, ['25176', 'kB'], "size");
    is($mem{rss},  ['16604', 'kB'], "rss");
};

subtest missing_procfile => sub {
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::proc_file = sub { '/this/path/should/not/exist/please' };
    my @out = Test2::Plugin::MemUsage::_collect_proc();
    is(\@out, [], "missing procfile -> empty");
};

subtest empty_procfile => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    close $fh;
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::proc_file = sub { $path };
    my @out = Test2::Plugin::MemUsage::_collect_proc();
    is(\@out, [], "empty file -> empty");
};

subtest no_vm_lines => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print $fh "Pid:    123\nName:   foo\nState:  R (running)\n";
    close $fh;
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::proc_file = sub { $path };
    my %mem = Test2::Plugin::MemUsage::_collect_proc();
    is($mem{peak}, ['NA', ''], "peak NA");
    is($mem{size}, ['NA', ''], "size NA");
    is($mem{rss},  ['NA', ''], "rss NA");
};

subtest tab_separator => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print $fh "VmPeak:\t  111 kB\nVmSize:\t  222 kB\nVmRSS:\t   333 kB\n";
    close $fh;
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::proc_file = sub { $path };
    my %mem = Test2::Plugin::MemUsage::_collect_proc();
    is($mem{peak}, ['111', 'kB'], "peak parsed with tab separator");
    is($mem{size}, ['222', 'kB'], "size parsed with tab separator");
    is($mem{rss},  ['333', 'kB'], "rss parsed with tab separator");
};

subtest partial_vm_lines => sub {
    my ($fh, $path) = tempfile(UNLINK => 1);
    print $fh "VmRSS:    1234 kB\n";  # only rss
    close $fh;
    no warnings 'redefine';
    local *Test2::Plugin::MemUsage::proc_file = sub { $path };
    my %mem = Test2::Plugin::MemUsage::_collect_proc();
    is($mem{rss},  ['1234', 'kB'], "rss parsed");
    is($mem{peak}, ['NA', ''],     "peak NA when missing");
    is($mem{size}, ['NA', ''],     "size NA when missing");
};

done_testing;
