=head2 NX::Common

Common utilities for perl code.

=cut

package NX::File;

use NX::Common qw( Debug Fatal Run RunOrFatal PrintOut ValueOr );

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(
    AbsPath
    OpenFileHandle
    ReadFile  WriteFile
    DeleteFile  MoveFile  CopyFile
    FindFreeFileName
    Symlink ReadSymlink
    );

use Cwd qw(abs_path);
use File::Basename qw(dirname);

sub MoveFile(%)
{
    my (%param) = @_;
    my ($source, $dest) = @param{qw(from to)};
    RunOrFatal(cmd => ['mv', $source, $dest]);
}

sub DeleteFile($)
{
    my ($file) = @_;
    Debug(3, "Deleting: '", $file, "'");
    unlink($file) || Fatal("Failed to delete '", $file, "': ", $!);
}

sub AbsPath($)
{
    my ($path) = @_;
    return abs_path($path);
}

sub OpenFileHandle($$)
{
    my ($direction, $file) = @_;

    if ($direction eq 'READ') { $direction = '<'; }
    if ($direction eq 'WRITE') { $direction = '>'; }

    my $fh;
    if (!open($fh, $direction, $file))
    {
        my $dir_text =
            ($direction eq '<') ? 'read' :
            ($direction eq '>') ? 'write' :
            '???';

        Fatal("Failed to ", $dir_text, " file '", $file, "': ", $!);
    }

    return $fh;
}

sub FindFreeFileName($$)
{
    my ($path, $extension) = @_;

    if (! -e "$path.$extension")
    {
        return "$path.$extension";
    }
    for (my $i = 1; $i < 1000; $i++)
    {
        if (! -e "$path.$i.$extension")
        {
            return "$path.$i.$extension";
        }
    }

    Fatal("Could not find free file name: $path.[Num].$extension");
}

sub ReadFile($)
{
    my ($file) = @_;
    my $fh = OpenFileHandle('READ', $file);
    my $out = ReadAll($fh);
    close($fh);
    return $out;
}

sub WriteFile(%)
{
    my (%param) = @_;
    my ($file, $content) = @param{qw(file content)};
    my $atomic = ValueOr($param{atomic}, 1);

    my $fh;
    my $tmp_file;
    if ($atomic)
    {
        $tmp_file = FindFreeFileName($file, "tmp");
        $fh = OpenFileHandle('WRITE', $tmp_file);
    }
    else
    {
        $fh = OpenFileHandle('WRITE', $file);
    }

    print({$sh} $file);
    close($fh);

    if ($atomic)
    {
        MoveFile(src => $tmp_file, dest => $file);
    }
}

sub IsPathRelative($)
{
    my ($path) = @_;
    return ($path =~ m{^\.}) ? 1 : 0;
}

sub ReadSymlink($)
{
    my ($file) = @_;
    if (! (-l $file))
    {
        Fatal("Tried to read symlink, but its not a symlink: ", $file);
    }

    my $link = readlink($file);
    if (IsPathRelative($link))
    {
        my $dir = dirname(AbsPath($file));
        $link = $dir . '/' . $link;
    }

    return AbsPath($link);
}

sub Symlink(%)
{
    my %param = @_;
    my ($from, $to, $overwrite) = @param{qw(from to overwrite)};

    if (-e $from)
    {
        if (-l $from)
        {
            my $link = ReadSymlink($from);
            Debug(4, "Link: ", $link);

            if ($link eq AbsPath($to))
            {
                Debug(4, "Link already exists: ", $link);
                return;
            }
            else
            {
                if ($overwrite)
                {
                    DeleteFile($from);
                }
                else
                {
                    Fatal(
                        "Cannot symlink '", $from, "' -> '", $to, "': Symlink allready exists: '",
                        $from, "' -> '", $link, "'"
                    );
                }
            }
        }
        else
        {
            Fatal("Cannot symlink '", $from, "' -> '", $to, "': File/dir already exists at '", $from, "'");
        }
    }

    Debug(5, "Creating symlink: '", $from, "' -> '", $to, "'");
    if (!symlink($to, $from))
    {
        Fatal("Symlink '", $from, "' -> '", $to, "' failed: ", ValueOr($!, "Unknown reason"));
    }
}

1;
