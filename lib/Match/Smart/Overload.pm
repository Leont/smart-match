package Match::Smart::Overload;
use strict;
use warnings FATAL => 'all';
use Carp qw/croak confess cluck/;
use XSLoader;

XSLoader::load(__PACKAGE__, __PACKAGE__->VERSION);

use overload 
	'~~' => sub {
		my ($self, undef, $rev) = @_;
		confess if not $rev;
		return ! !$self->() for $_[1];
	},
	bool => 1 ? \&_boolean
	: sub {
		my $self = shift;
		return ! !$self->();
	},
	fallback => 1;

sub new {
	my ($class, $sub) = @_;
	return bless $sub, $class;
}

1;

# A class for closure based matcher objects.

__END__

=method new($sub)

Creates a new matcher based on C<$sub>. $sub will be called with the left hand side in C<$_>.

