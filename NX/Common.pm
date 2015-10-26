=head2 NX::Common

Common utilities for perl code.

=cut

package NX::Common;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    CommonInit RequireRoot
    Run RunOrFatal
    Debug PrintOut Fatal
    ValueOr
    Env ScriptDirectory
    ConcatText
    ReadAll
    );

use Symbol qw(gensym);
use IPC::Open3 qw(open3);
use IO::Select;
use POSIX qw(:sys_wait_h);
use Data::Dump qw(dump);
use Cwd qw(getcwd abs_path);
use File::Basename qw(dirname);

use strict;
use warnings;

sub Env($;$);

# Useful globals
my $debug_level = Env('DEBUG_LEVEL', 0);
my $running_script = $0;
my $initial_working_dir = getcwd();
my $script_dir = abs_path(dirname($running_script));

sub ValueOr($$)
{
    my ($value, $default) = @_;

    if (!defined($value))
    {
        return $default;
    }
    else
    {
        return $value;
    }
}

sub Env($;$)
{
    my ($env, $default) = @_;
    return ValueOr($ENV{$env}, $default);
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
    $SIG{INT} = sub { Fatal("Caught a SIGINT signal: $!"); };
    $SIG{TERM} = sub { Fatal("Caught a SIGTERM signal: $!"); };
}

sub IsRoot()
{
    return $> == 0;
}

sub RequireRoot()
{
    if (!IsRoot())
    {
        PrintOut("Root access is required, restarting script with sudo...");
        chdir($initial_working_dir);
        exec('sudo', $0, @ARGV);
    }
}

sub ScriptDirectory()
{
    return $script_dir;
}

sub ReadAll($)
{
    my ($fh) = @_;
    return do { local $/; <$fh> };
}

sub Run(%)
{
    my %param = @_;
    my ($cmd, $in, $working_dir) = @param{qw(cmd in working_dir)};

    if (!$cmd) { FATAL("Requires cmd parameter"); }
    if (ref($cmd) ne 'ARRAY') { FATAL("The 'cmd' parameter must be an array reference"); }

    Debug(2, "Running: ", $cmd);

    my $orig_dir = undef;
    if (defined($working_dir))
    {
        $orig_dir = getcwd();
        Debug(3, "Switching working dir: ", $orig_dir, " -> ", $working_dir);
        chdir($working_dir);
    }

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

    if (defined($orig_dir))
    {
        Debug(3, "Switching working dir back: ", $working_dir, " -> ", $orig_dir);
        chdir($orig_dir);
    }

    return {
        out => $out,
        err => $err,
        both => $both,
        exit_code => $exit_code, pid => $pid
    };
}

sub RunOrFatal
{
    my %param = @_;
    my $result = Run(@_);

    if ($result->{exit_code} == 0)
    {
        return $result;
    }

    my ($cmd, $in, $working_dir) = @param{qw(cmd in working_dir)};
    Fatal(
        "Failed to run '@$cmd', exited with code: $result->{exit_code}\n" .
        "Output:\n" .
        ('-' x 100) . "\n" .
        $result->{both} . "\n" .
        ('-' x 100) . "\n"
    );
}


1;
