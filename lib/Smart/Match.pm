package Smart::Match;

use 5.010001;
use strict;
use warnings;
use experimental 'smartmatch';

use Carp qw/croak/;
use List::Util 1.33 qw//;
use Scalar::Util qw(blessed looks_like_number refaddr);

use Smart::Match::Overload;

use Sub::Exporter::Progressive -setup => {
	exports => [qw/
		match delegate
		always never
		any all none one
		true false
		number integer even odd
		more_than less_than at_least at_most positive negative range
		numwise stringwise
		string string_length
		object instance_of ref_type
		array array_length tuple head sequence contains contains_any sorted sorted_by
		hash hash_keys hash_values sub_hash hashwise
		address value
	/],
	groups => {
		junctive => [qw/any all none one/],
		definite => [qw/always never/],
		boolean  => [qw/true false/],
		numeric  => [qw/number integer even odd more_than less_than at_least at_most/],
		compare  => [qw/numwise stringwise hashwise/],
		meta     => [qw/match delegate/],
		string   => [qw/string string_length/],
		refs     => [qw/object instance_of ref_type/],
		arrays   => [qw/array array_length tuple head sequence contains contains_any sorted/],
		hashes   => [qw/hash hash_keys hash_values sub_hash/],
		direct   => [qw/address value/],
	},
};

## no critic (Subroutines::ProhibitSubroutinePrototypes,ValuesAndExpressions::ProhibitConstantPragma)
sub match (&) {
	my $sub = shift;

	return Smart::Match::Overload->new($sub);
}

sub _matchall (&@) {
	my $sub = shift;
	croak 'No arguments given to match' if not @_;
	if (wantarray) {
		return map { $sub->($_) } @_;
	}
	else {
		croak 'Can\'t use multiple matchers in scalar context' if @_ > 1;
		return $sub->($_[0]);
	}
}

sub delegate (&@) {
	my ($sub, $match) = @_;
	return match { return $_ ~~ $match for $sub->() };
}

sub any {
	my @possibilities = @_;
	return match {
		for my $candidate (@possibilities) {
			return 1 if $_ ~~ $candidate;
		}
		return;
	};
}

sub all {
	my @possibilities = @_;
	return match {
		for my $candidate (@possibilities) {
			return if not $_ ~~ $candidate;
		}
		return 1;
	};
}

sub none {
	my @possibilities = @_;
	return match {
		for my $candidate (@possibilities) {
			return if $_ ~~ $candidate;
		}
		return 1;
	};
}

sub one {
	my @possibilities = @_;
	return match {
		my $count = 0;
		for my $candidate (@possibilities) {
			$count++ if $_ ~~ $candidate;
			return if $count > 1;
		}
		return $count == 1;
	};
}

use constant always => match { 1 };
use constant never  => match { };

use constant true  => match { $_ };
use constant false => match { not $_ };

use constant number  => match { looks_like_number($_) };
use constant integer => match { looks_like_number($_) and int == $_ };

use constant even => match { scalar integer and $_ % 2 == 0 };
use constant odd  => match { scalar integer and $_ % 2 == 1 };

sub more_than {
	my $cutoff = shift;
	return match { looks_like_number($_) and $_ > $cutoff };
}

sub at_least {
	my $cutoff = shift;
	return match { looks_like_number($_) and $_ >= $cutoff };
}

sub less_than {
	my $cutoff = shift;
	return match { looks_like_number($_) and $_ < $cutoff };
}

sub at_most {
	my $cutoff = shift;
	return match { looks_like_number($_) and $_ <= $cutoff };
}

sub range {
	my ($bottom, $top) = @_;
	return all(at_least($bottom), at_most($top));
}

use constant positive => more_than(0);
use constant negative => less_than(0);

sub numwise {
	croak 'No number given' if not @_;
	return _matchall { my $other = shift ; match { scalar number and $_ == $other } } @_;
}

use constant string => match { ref() ? blessed($_) && overload::OverloadedStringify($_) : defined };

sub string_length {
	my $match = shift;
	return match { scalar string and length $_ ~~ $match };
}

sub stringwise {
	croak 'No number given' if not @_;
	return _matchall { my $other = shift; match { scalar string and $_ eq $other } } @_;
}

use constant object => match { blessed($_) };

sub instance_of {
	my $class = shift;
	return match { blessed($_) and $_->isa($class) };
}

sub ref_type {
	my $type = shift;
	return match { ref eq $type };
}

sub address {
	my $addr = refaddr($_[0]);
	return match { refaddr($_) == $addr };
}

use constant array => ref_type('ARRAY');

sub array_length {
	my $match = shift;
	return match { scalar array and @{$_} + 0 ~~ $match };
}

sub tuple {
	my @entries = @_;
	return match { scalar array and $_ ~~ @entries };
}

sub sequence {
	my $matcher = shift;
	return match { scalar array and List::Util::all { $_ ~~ $matcher } @{$_} };
}

sub head {
	my @entries = @_;
	return match { scalar array_length(at_least(scalar @entries)) and [ @{$_}[ 0..$#entries ] ] ~~ @entries };
}

sub contains {
	my @matchers = @_;
	return match {
		my $lsh = $_;
		$_ ~~ array and List::Util::all { my $matcher = $_; List::Util::any { $_ ~~ $matcher } @{$lsh} } @matchers;
	};
}

sub contains_any {
	my @matchers = @_;
	return match {
		my $lsh = $_;
		$_ ~~ array and List::Util::any { my $matcher = $_; List::Util::any { $_ ~~ $matcher } @{$lsh} } @matchers;
	};
}

sub sorted {
	my $matcher = shift;
	return match { scalar array and [ sort @{$_} ] ~~ $matcher };
}

sub sorted_by {
	my ($sorter, $matcher) = @_;
	return match { scalar array and [ sort { $sorter->($a, $b) } @{$_} ] ~~ $matcher };
}

use constant hash => ref_type('HASH');

sub hash_keys {
	my $matcher = shift;
	return match { scalar hash and [ keys %{$_} ] ~~ $matcher };
}

sub hash_values {
	my $matcher = shift;
	return match { scalar hash and [ values %{$_} ] ~~ $matcher };
}

sub sub_hash {
	my $hash = shift;
	return match {
		my $lhs = $_; # for grep { }

		$lhs ~~ hash and keys %{$lhs} >= keys %{$hash} and List::Util::all { exists $lhs->{$_} } keys %{$hash} and [ @{$lhs}{keys %{$hash}} ] ~~ [ values %{$hash} ];
	};
}

sub hashwise {
	my $hash = shift;
	return match { scalar hash and hash_keys(sorted([ sort keys %{$hash} ])) and [ @{$_}{keys %{$hash}} ] ~~ [ values %{$hash} ] };
}

sub value {
	my $value = shift;
	return $value if blessed($value);
	given (ref $value) {
		when ('') {
			return $value;
		}
		when ('ARRAY') {
			return tuple(map { value($_) } @{$value});
		}
		when ('HASH') {
			my %match = map { ( $_ => value($value->{$_}) ) } keys %{$value};
			return hashwise(\%match);
		}
		when ([qw/CODE SCALAR REF/]) {
			return address($value);
		}
		when ([qw/GLOB IO FORMAT/]) {
			croak "Can't match \L$_";
		}
		default {
			croak "Don't know what you want me to do with a $_";
		}
	}
}

1;

# ABSTRACT: Smart matching utilities

__END__

=head1 SYNOPSIS

 given ($foo) {
     say "We've got a positive number" when positive;
     say "We've got an array" when array;
     say "We've got a non-empty string" when string_length(positive);
 }

=head1 DESCRIPTION

This module provides a number of helper functions for smartmatching. Some are simple functions that directly match the left hand side, such as

 $foo ~~ positive
 $bar ~~ array

Others are higher-order matchers that take one or more matchers as an argument, such as

 $foo ~~ string_length(positive)
 $bar ~~ any(array, hash)

Do note that ordinary values are matchers too, so

 $baz ~~ any(1,2,3)

will also do what you mean.

=func always()

This always matches.

=func never()

This never matches.

=func any(@matchers)

This matches if the left hand side matches any of C<@matchers>.

=func all(@matchers)

This matches if the left hand side matches all of C<@matchers>.

=func none(@matchers)

This matches if the left hand side matches none of C<@matchers>.

=func one(@matchers)

This matches if the left hand side matches exactly one of C<@matchers>.

=func true()

This matches if the left hand side is true.

=func false()

This matches if the left hand side is false.

=func number()

This matches if the left hand side is a number.

=func integer()

This matches if the left hand side is an integer.

=func even()

This matches if the left hand side is even.

=func odd()

This matches if the left hand side is odd.

=func more_than($cutoff)

Matches if the left hand side is more than C<$cutoff>.

=func at_least($cutoff)

Matches if the left hand side is at least C<$cutoff>.

=func less_than($cutoff)

Matches if the left hand side is less than C<$cutoff>.

=func at_most($cutoff)

Matches if the left hand side is at most C<$cutoff>.

=func positive()

This is a synonym for C<more_than(0)>.

=func negative()

This is a synonym for C<less_than(0)>.

=func range($bottom, $top)

A synonym for C<all(at_least($bottom, at_most($top))>.

=func numwise($number, ...)

Matches the left hand side numerically with $number if that makes sense, returns false otherwise. If given multiple numbers it will return multiple matchers.

=func string()

Matches any string, that is any defined value that's that's not a reference without string overloading.

=func stringwise($string, ...)

Matches the left hand side lexographically with $string if that makes sense, returns false otherwise. If given multiple strings it will return multiple matchers.

=func string_length($matcher)

Matches the string's length 

=func object()

Matches any object (that is, a blessed reference).

=func instance_of($class)

Matches any instance of class C<$class>.

=func ref_type($type)

Matches any unblessed reference of type $type.

=func array()

Matches any unblessed array.

=func array_length($matcher)

Matches any unblessed array whose length matches C<$matcher>.

=func tuple(@entries)

Matches a list whose elements match C<@entries> one by one.

=func head(@elements)

Matches a list whose head elements match C<@entries> one by one.

=func sequence($matcher)

Matches a list whose elements all match C<$matcher>.

=func contains(@matchers)

Matches a list that contains a matching element for all of C<@matchers>.

=func contains_any(@matcher)

Matches a list that contains a matching element for any of C<@matchers>.

=func sorted($matcher)

Sorts a list and matches it against C<$matcher>.

=func sorted_by($sorter, $matcher)

Sorts a list using $sorter and matches it against C<$matcher>.

=func hash()

Matches any unblessed hash.

=func hashwise($hashref)

Matches a hash for against C<$hashref>. The keys must be identical, and all keys in the hash much smartmatch the keys in $hashref.

=func hash_keys($matcher)

Match a list of hash keys against C<$matcher>.

=func hash_values($matches)

Match a list of hash values against C<$matcher>

=func sub_hash({ key => $matcher, ... })

Matches each hash entry against a the corresponding matcher.

=func match { ... }

Create a new matching function. It will be run with the left-hand side in C<$_>.

=func delegate { ... } $matcher

Run the block, and then match the return value against C<$matcher>.

=func address($var)

Matches if the left hand side has the same address as $var.

=func value

This with match on recursive value equivalence. It will use other matchers such as tuple, hashwise and address to achieve this.
