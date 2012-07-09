package MyTools;

use strict;
use warnings;
use feature ':5.10';

use Carp;

our(@ISA, @EXPORT, @EXPORT_OK, $VERSION);
require Exporter;
@ISA = qw|Exporter|;
@EXPORT = qw|slurp spew|;
@EXPORT_OK = qw|rc ls|;
$VERSION = '1.0';

sub ls{
    my ($dir) = @_;
	
    opendir my $dh, $dir or croak "Can't open dir [$dir]: $!";
	
    my @list = grep !/^\.+$/, readdir $dh;
	
    closedir $dh;
	
	return @list;
}
sub rc{
    my ($file, $href) = @_;
	
	open my $fh, '<', $file or croak "Can't read file [$file]: $!";
	
	while(<$fh>){
		next if /^\s*$/ || /^#/;
		chomp;
		my ($key, $value) = split /\s*=\s*/, $_, 2;
		for($value){s/\${([A-Z_]+)}/$ENV{$1}/;s/\$(\w+|{.+})/$$href{$1}/g}
		#($value) = map{s/\${([A-Z_]+)}/$ENV{$1}/;s/\$(\w+|{.+})/$$href{$1}/g;$_} $value;
		$$href{$key} = $value;
	}
	
	close $fh;
}
sub slurp{
    my ($file) = @_;
	my @content;
	my $bin = $file =~ s/^://;
	
    open my $fh, '<', $file or croak "Can't open file [$file]: $!";
	binmode $fh if $bin;
	
	@content = <$fh>;
	
	close $fh;
	
	return wantarray ? @content : join '', @content;
}
sub spew{
    my ($file, $content, $mode) = @_;
	my $bin = $file =~ s/^://;
	
    open my $fh, $mode||'>', $file or croak "Can't open file [$file]: $!";
	binmode $fh if $bin;
	
	print $fh $content;
	
	close $fh;
}
1;