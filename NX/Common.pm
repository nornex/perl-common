=head2 NX::Common

Common utilities for perl code.

=cut

package NX::Common;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    CommonInit
    Run Debug PrintOut Fatal
    Env
    ConcatText
    );

use Symbol qw(gensym);
use IPC::Open3 qw(open3);
use IO::Select;
use POSIX ":sys_wait_h";
use Data::Dump qw(dump);

use strict;
use warnings;

sub CommonScriptSettings()
{
    $SIG{__DIE__} = sub { Carp::confess( @_ ) };
    $SIG{__WARN__} = sub { Carp::confess( @_ ) };
}

sub Env($;$)
{
    my ($env, $default) = @_;
    my $value = $ENV{$env};
    if (!defined($value))
    {
        return $default;
    }
    else
    {
        return $value;
    }
}

sub ConcatText(@)
{
    my (@concat) = @_;

    my $out = '';
    foreach my $item (@concat)
    {
        if (!defined($item))
        {
            $out .= 'undef';
        }
        elsif (ref($item) eq '')
        {
            $out .= $item;
        }
        else
        {
            my $dump = dump($item);
            $dump =~ s/\s*\n\s*/ /g;
            $out .= $dump;
        }
    }
    return $out;
}

my $debug_level = Env('DEBUG_LEVEL', 0);
sub DebugLevel()
{
    return $debug_level;
}

sub Debug($@)
{
    my ($level, @concat) = @_;
    if ($level > DebugLevel()) { return; }

    my $text = ConcatText(@concat);

    my ($package, $filename, $line) = caller(0);
    print((' ' x $level) . "$text\t($filename:$line)\n");
}

sub PrintOut(@)
{
    print(ConcatText(@_) . "\n");
}

sub Fatal(@)
{
    my $text = "FATAL: " . ConcatText(@_) . "\n";
    if ($debug_level > 0)
    {
        die($text);
    }
    else
    {
        print({*STDERR} $text);
        exit 1;
    }
}

sub CommonInit()
{
    $SIG{__DIE__} = sub { Carp::confess( @_ ) };
    $SIG{__WARN__} = sub { Carp::confess( @_ ) };
    $SIG{INT} = sub { FATAL("Caught a SIGINT signal: $!"); };
    $SIG{TERM} = sub { FATAL("Caught a SIGTERM signal: $!"); };
}

sub ReadAll($)
{
    my ($fh) = @_;
    return do { local $/; <$fh> };
}

sub Run(%)
{
    my %param = @_;
    my ($cmd, $in) = @param{qw(cmd in)};

    if (!$cmd) { FATAL("Requires cmd parameter"); }
    if (ref($cmd) ne 'ARRAY') { FATAL("The 'cmd' parameter, must be an array reference"); }

    Debug(2, "Running: ", $cmd);
    my ($in_fh, $out_fh, $err_fh) = (gensym(), gensym(), gensym());
    my $pid = open3($in_fh, $out_fh, $err_fh, @$cmd);
    if (!defined($pid))
    {
        Fatal("Failed to run '@$cmd': $!");
    }

    Debug(3, "PID is: ", $pid);

    if (defined($in))
    {
        print({$in_fh} $in);
    }
    close($in_fh);

    my $select = IO::Select->new();
    $select->add($out_fh);
    $select->add($err_fh);

    my ($out, $err, $both) = ('', '', '');
    while (1)
    {
        my $stop = (waitpid($pid, WNOHANG) == 0) ? 0 : 1;

        my @ready = $select->can_read(0.1);
        foreach my $fh (@ready)
        {
            my $chunk;
            my $count = read($fh, $chunk, 1024);
            if (!$count || !defined($chunk)) { next; }

            if ($fh == $out_fh)
            {
                $out .= $chunk;
                if (DebugLevel() >= 5)
                {
                    map { Debug(5, 'OUT: ', $_) } split(/\n/, $chunk);
                }

            }
            if ($fh == $err_fh)
            {
                $err .= $chunk;
                if (DebugLevel() >= 5)
                {
                    map { Debug(5, 'ERR: ', $_) } split(/\n/, $chunk);
                }
            }
            $both .= $chunk;
        }

        if ($stop)
        {
            last;
        }
    }
    my $exit_code = $? >> 8;

    my $remaining_out = ReadAll($out_fh);
    $out .= $remaining_out;
    $both .= $remaining_out;

    my $remaining_err = ReadAll($err_fh);
    $err .= $remaining_err;
    $both .= $remaining_err;

    Debug(3, "Exit code was: ", $exit_code);
    close($out_fh);
    close($err_fh);

    return {
        out => $out,
        err => $err,
        both => $both,
        exit_code => $exit_code, pid => $pid
    };
}

1;
