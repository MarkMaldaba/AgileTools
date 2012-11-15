# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2012 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jollamobile.com>

=head1 NAME

Bugzilla::Extension::AgileTools::WebService::Pool

=head1 DESCRIPTION

Web service methods available under namespace 'Agile.Pool'.

=cut

use strict;
use warnings;

package Bugzilla::Extension::AgileTools::WebService::Pool;

use base qw(Bugzilla::WebService);

use Bugzilla::Error;
use Bugzilla::WebService::Bug;

use Bugzilla::Extension::AgileTools::Sprint;

use Bugzilla::Extension::AgileTools::Util qw(get_team get_role get_user);
use Bugzilla::Extension::AgileTools::WebService::Util;

# Webservice field type mapping
use constant FIELD_TYPES => {
    "id" => "int",
    "name" => "string",
};

=head1 METHODS

=over

=item C<get>

    Description: Pool info
    Params:      id - Sprint ID
    Returns:     { name => 'pool name', bugs => [ list of bugs... ] }

=cut

sub get {
    my ($self, $params) = @_;
    ThrowCodeError('param_required', {
            function => 'Agile.Pool.get',
            param => 'id'})
        unless defined $params->{id};
    my $pool = Bugzilla::Extension::AgileTools::Pool->check({
            id => $params->{id}});
    my @bugs;
    foreach my $bug (sort { $a->pool_order cmp $b->pool_order } @{$pool->bugs}) {
        my $bug_hash = Bugzilla::WebService::Bug::_bug_to_hash(
            $self, $bug, $params);
        $bug_hash->{pool_order} = $self->type("int", $bug->pool_order);
        $bug_hash->{pool_id} = $self->type("int", $bug->pool_id);
        push(@bugs, $bug_hash);
    }
    my $hash = object_to_hash($self, $pool, FIELD_TYPES);
    $hash->{bugs} = \@bugs;

    return $hash;
}


=item C<add_bug>

    Description: Add new bug into the pool
    Params:      id - Pool id
                 bug_id - Bug id
                 order - (optional) Order of the bug in pool, last if not given
    Returns:     ???

=cut

sub add_bug {
    my ($self, $params) = @_;

    ThrowCodeError('param_required', {
            function => 'Agile.Pool.add_bug',
            param => 'id'})
        unless defined $params->{id};
    ThrowCodeError('param_required', {
            function => 'Agile.Pool.add_bug',
            param => 'bug_id'})
        unless defined $params->{bug_id};

    my $pool = Bugzilla::Extension::AgileTools::Pool->check({
            id => $params->{id}});

    my $changed = $pool->add_bug($params->{bug_id}, $params->{order});
    return { name => $pool->name, changed => $changed };
}

=item C<remove_bug>

    Description: Remove bug from the pool
    Params:      id - Pool ID
                 bug_id - Bug ID
    Returns:     ???

=cut

sub remove_bug {
    my ($self, $params) = @_;

    ThrowCodeError('param_required', {
            function => 'Agile.Pool.remove_bug',
            param => 'id'})
        unless defined $params->{id};
    ThrowCodeError('param_required', {
            function => 'Agile.Pool.remove_bug',
            param => 'bug_id'})
        unless defined $params->{bug_id};

    my $pool = Bugzilla::Extension::AgileTools::Pool->check({
            id => $params->{id}});

    my $changed = $pool->remove_bug($params->{bug_id});
    return { name => $pool->name, changed => $changed };
}

1;

__END__

=back

=head1 SEE ALSO

L<Bugzilla::WebService>

