package MyLog;

use strict;
use feature ':5.10';
use Carp 'croak';
use Fcntl ':flock';

# Supported log levels
my $LEVEL = {trace => 1, debug => 2, info => 3, warn => 4, error => 5, fatal => 6};

sub trace { shift->log('trace', @_) }
sub debug { shift->log('debug', @_) }
sub info  { shift->log('info',  @_) }
sub warn  { shift->log('warn',  @_) }
sub error { shift->log('error', @_) }
sub fatal { shift->log('fatal', @_) }

sub format{
	my ($self, $level, @msg) = @_;
	return "[$level] ".join("\r\n", @msg)."\r\n";
}
sub handle{
	my ($self) = @_;
	
	open my $fh, '>>', $self->{'file'} or croak "Can't open file [$self->{'file'}]: $!";
	binmode $fh;
	
	return $fh;
}
sub is_level{
	my ($self, $level) = @_;
	return unless $level;
	$level = lc $level;
	return $LEVEL->{$level} >= $LEVEL->{$self->{'level'}};
}
sub new{
    my ($class, $href) = @_;
	my %default = (level => 'debug', file => 'log.log');
	
    my $self = {map {$_ => $$href{$_} || $default{$_}} keys %default};
    bless $self, ref $class || $class;
	
    return $self;
}
sub level{
	my ($self, $value) = @_;
	return $self->{'level'} unless defined $value;
	return $self->{'level'} = $value;
}
sub log{
	my ($self, $level, @msg) = @_;

	$level = lc $level;
	return $self unless $level && $self->is_level($level);

	my $fh = $self->handle;
	flock $fh, LOCK_EX;

	syswrite $fh, $self->format($level, @msg);

	flock $fh, LOCK_UN;
	close $fh;

	return $self;
}