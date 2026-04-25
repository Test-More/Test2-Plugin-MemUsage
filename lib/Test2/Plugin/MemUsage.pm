package Test2::Plugin::MemUsage;
use strict;
use warnings;

our $VERSION = '0.002004';

use Test2::API qw/test2_add_callback_exit/;

my $ADDED_HOOK = 0;

sub import {
    return if $ADDED_HOOK++;

    test2_add_callback_exit(\&send_mem_event);
}

sub proc_file { "/proc/$$/status" }

sub _empty_mem { (peak => ['NA', ''], size => ['NA', ''], rss => ['NA', '']) }

sub _collect_proc {
    my $file = proc_file();
    return unless -e $file;

    my $stats;
    {
        open(my $fh, '<', $file) or warn("Could not open file '$file' (<): $!"), return;
        local $/;
        $stats = <$fh>;
        close($fh) or warn "Could not close file '$file': $!";
    }

    return unless $stats;

    my %mem = _empty_mem();
    $mem{peak} = [$1, $2] if $stats =~ m/VmPeak:\s+(\d+)\s+(\S+)/;
    $mem{size} = [$1, $2] if $stats =~ m/VmSize:\s+(\d+)\s+(\S+)/;
    $mem{rss}  = [$1, $2] if $stats =~ m/VmRSS:\s+(\d+)\s+(\S+)/;

    return %mem;
}

sub ps_command { "ps -o rss=,vsz= -p $$" }

sub _collect_ps {
    my $cmd = ps_command();
    my $out = `$cmd 2>/dev/null`;
    return unless defined $out && length $out;

    my ($rss, $vsz) = $out =~ /^\s*(\d+)\s+(\d+)\s*$/m
        or return;

    my %mem = _empty_mem();
    $mem{rss}  = [$rss, 'kB'];
    $mem{size} = [$vsz, 'kB'];
    return %mem;
}

sub _collect_win32 {
    return unless eval { require Win32::Process::Memory; 1 };

    my $info = eval { Win32::Process::Memory::GetProcessMemoryInfo($$) }
        or return;

    my $rss  = $info->{WorkingSetSize}     || 0;
    my $peak = $info->{PeakWorkingSetSize} || 0;
    my $size = $info->{PagefileUsage}      || 0;

    my %mem = _empty_mem();
    $mem{rss}  = [int($rss  / 1024), 'kB'] if $rss;
    $mem{peak} = [int($peak / 1024), 'kB'] if $peak;
    $mem{size} = [int($size / 1024), 'kB'] if $size;
    return %mem;
}

sub _collector_for_os {
    my $os = shift // $^O;
    return \&_collect_proc  if $os eq 'linux' || $os eq 'cygwin' || $os eq 'gnukfreebsd';
    return \&_collect_ps    if $os eq 'darwin' || $os =~ /bsd$/;
    return \&_collect_win32 if $os eq 'MSWin32';
    return undef;
}

sub collect_mem { my $c = _collector_for_os(); $c ? $c->() : () }

sub send_mem_event {
    my ($ctx, $real, $new) = @_;

    my %mem = collect_mem();
    return unless %mem;
    return unless grep { $_->[0] ne 'NA' } values %mem;

    $mem{details} = "rss:  $mem{rss}->[0]$mem{rss}->[1]\nsize: $mem{size}->[0]$mem{size}->[1]\npeak: $mem{peak}->[0]$mem{peak}->[1]";

    $ctx->send_ev2(
        memory => \%mem,
        about  => {package => __PACKAGE__, details => $mem{details}},
        info   => [{tag => 'MEMORY', details => $mem{details}}],

        harness_job_fields => [
            map {
                my $k = $_;
                my ($v, $u) = @{$mem{$k}};
                +{
                    name    => "mem_$k",
                    details => "$v$u",
                    data    => {value => ($v eq 'NA' ? undef : $v + 0), units => $u},
                };
            } qw/rss size peak/,
        ],
    );
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Test2::Plugin::MemUsage - Collect and display memory usage information.

=head1 CAVEAT - UNIX ONLY

Currently this only works on unix systems that provide C</proc/PID/status>
access. For all other systems this plugin is essentially a no-op.

=head1 DESCRIPTION

This plugin will collect memory usage info from C</proc/PID/status> and display
it for you when the test is done running.

=head1 SYNOPSIS

    use Test2::Plugin::MemUsage;

This is also useful at the command line for 1-time use:

    $ perl -MTest2::Plugin::MemUsage path/to/test.t

Output:

    # rss:  36708kB
    # size: 49836kB
    # peak: 49836kB

=head1 SOURCE

The source code repository for Test2-Plugin-MemUsage can be found at
F<https://github.com/Test-More/Test2-Plugin-MemUsage/>.

=head1 MAINTAINERS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 AUTHORS

=over 4

=item Chad Granum E<lt>exodist@cpan.orgE<gt>

=back

=head1 COPYRIGHT

Copyright 2019 Chad Granum E<lt>exodist@cpan.orgE<gt>.

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

See F<http://dev.perl.org/licenses/>

=cut
