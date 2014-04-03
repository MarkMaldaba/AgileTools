# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# Copyright (C) 2012 Jolla Ltd.
# Contact: Pami Ketolainen <pami.ketolainen@jollamobile.com>

=head1 NAME

Bugzilla::Extension::AgileTools::Sprint - Sprint Object class

=head1 SYNOPSIS

    use Bugzilla::Extension::AgileTools::Sprint;

=head1 DESCRIPTION

Sprint object contains the bug pool additional data related to sprints like
team and start and end dates.

=head1 FIELDS

=over

=item C<start_date> (mutable) - Start date of the sprint

=item C<end_date> (mutable) - End date of the sprint

=item C<pool_id> - ID of the pool related to this sprint

=item C<team_id> - ID of the team owning this sprint

=item C<capacity> (mutable) - Estimated work capacity for the sprint

=item C<committed> - Has the sprint been committed or not

=item C<items_on_commit> - Number of items in sprint at the time of commit

=item C<items_on_close> - Number of open items at the time of closing

=item C<resolved_on_close> - Number of resolved items at the time of closing

=item C<effort_on_commit> - Effort used on items at the time of commit

=item C<estimate_on_commit> - Remaining effort estimate of items at the time of
                              commit

=item C<effort_on_close> - Effort used on items at the time of closing

=item C<estimate_on_close> - Remaining effort estimate of items at the time of
                             closing

=back

=cut

use strict;
package Bugzilla::Extension::AgileTools::Sprint;

use base qw(Bugzilla::Object);

use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Hook;
use Bugzilla::Util qw(datetime_from detaint_natural trim);


use constant DB_TABLE => 'agile_sprint';

use constant LIST_ORDER => 'start_date';

sub DB_COLUMNS {
    my $dbh = Bugzilla->dbh;
    my @columns = (qw(
        id
        team_id
        capacity
        committed
        items_on_commit
        items_on_close
        resolved_on_close
        effort_on_commit
        estimate_on_commit
        effort_on_close
        estimate_on_close
    ),
    $dbh->sql_date_format('start_date', '%Y-%m-%d') . ' AS start_date',
    $dbh->sql_date_format('end_date', '%Y-%m-%d') . ' AS end_date',
    );
    return @columns;
}

use constant NUMERIC_COLUMNS => qw(
    team_id
    capacity
    committed
    items_on_commit
    items_on_close
    resolved_on_close
    effort_on_commit
    estimate_on_commit
    effort_on_close
    estimate_on_close
);

use constant DATE_COLUMNS => qw(
    start_date
    end_date
);

use constant UPDATE_COLUMNS => qw(
    start_date
    end_date
    capacity
    committed
    items_on_commit
    items_on_close
    resolved_on_close
    effort_on_commit
    estimate_on_commit
    effort_on_close
    estimate_on_close
);

use constant VALIDATORS => {
    start_date => \&_check_start_date,
    end_date => \&_check_end_date,
    team_id => \&_check_number,
    capacity => \&Bugzilla::Object::check_time,
    committed => \&Bugzilla::Object::check_boolean,
    items_on_commit => \&_check_number,
    items_on_close => \&_check_number,
    resolved_on_close => \&_check_number,
    effort_on_commit => \&Bugzilla::Object::check_time,
    estimate_on_commit => \&Bugzilla::Object::check_time,
    effort_on_close => \&Bugzilla::Object::check_time,
    estimate_on_close => \&Bugzilla::Object::check_time,
};

use constant VALIDATOR_DEPENDENCIES => {
    # Start date is checked against existing sprint end dates
    start_date => ['team_id'],
    # End date is checked against start date
    end_date => ['start_date'],
};

use constant EXTRA_REQUIRED_FIELDS => qw(
);

# Accessors
###########

sub start_date  { return $_[0]->{start_date}; }
sub end_date    { return $_[0]->{end_date}; }
sub team_id     { return $_[0]->{team_id}; }
sub capacity    { return $_[0]->{capacity}; }
sub committed          { return $_[0]->{committed}; }
sub items_on_commit    { return $_[0]->{items_on_commit}; }
sub items_on_close     { return $_[0]->{items_on_close}; }
sub resolved_on_close  { return $_[0]->{resolved_on_close}; }
sub effort_on_commit   { return $_[0]->{effort_on_commit}; }
sub estimate_on_commit { return $_[0]->{estimate_on_commit}; }
sub effort_on_close    { return $_[0]->{effort_on_close}; }
sub estimate_on_close  { return $_[0]->{estimate_on_close}; }

sub team {
    my $self = shift;
    if (!defined $self->{team}) {
        $self->{team} = Bugzilla::Extension::AgileTools::Team->new(
            $self->team_id);
    }
    return $self->{team};
}

sub pool {
    my $self = shift;
    if (!defined $self->{pool}) {
        $self->{pool} = Bugzilla::Extension::AgileTools::Pool->new(
            $self->id);
    }
    return $self->{pool};
}

sub name {
    my $self = shift;
    if (!defined $self->{name}) {
        $self->{name} = $self->pool->name;
    }
    return $self->{name};
}

# Mutators
##########

sub set_start_date  { $_[0]->set('start_date', $_[1]); }
sub set_end_date    { $_[0]->set('end_date', $_[1]); }
sub set_capacity    { $_[0]->set('capacity', $_[1]); }

# Validators
############

sub _check_start_date {
    my ($invocant, $date, undef, $params) = @_;
    $date = trim($date);
    $date || ThrowUserError("agile_missing_field", {field=>'start_date'});

    my $start_dt = datetime_from($date);
    $start_dt || ThrowUserError("agile_invalid_field", {
            field => "start_date", value => $date});
    $date = $start_dt->ymd;
    return $date;
}

sub _check_end_date {
    my ($invocant, $date, undef, $params) = @_;
    $date = trim($date);
    $date || ThrowUserError("agile_missing_field", {field=>'end_date'});

    my $end_dt = datetime_from($date);
    $end_dt || ThrowUserError("agile_invalid_field", {
            field => "end_dt", value => $date});

    my $start_dt = ref $invocant ?
            datetime_from($invocant->start_date) :
            datetime_from($params->{start_date});

    ThrowUserError("agile_sprint_end_before_start") if ($end_dt < $start_dt);

    my $id = ref $invocant ? $invocant->id : 0;
    my $team_id = ref $invocant ? $invocant->team_id : $params->{team_id};
    my $start_date = $start_dt->ymd;
    $date = $end_dt->ymd;

    my $dbh = Bugzilla->dbh;
    my $overlaping = $dbh->selectrow_array(
        'SELECT id '.
          'FROM agile_sprint '.
         'WHERE team_id = ? AND id != ? AND ('.
               '(start_date > ? AND start_date < ?) OR '.
               '(end_date > ? AND end_date < ?))',
        undef, ($team_id, $id, $start_date, $date, $start_date, $date ));
    ThrowUserError("agile_sprint_overlap",
            {sprint => Bugzilla::Extension::AgileTools::Sprint->new($overlaping)})
        if ($overlaping);
    return $date;
}

# TODO Move overlaping check to separate validator and check both start and
#      end at the same time.

sub _check_number {
    my ($invocant, $value, $field) = @_;
    ThrowUserError("invalid_parameter", {name=>$field, err=>'Not a number'})
        unless detaint_natural($value);
    return $value;
}

sub create {
    my ($class, $params) = @_;

    $class->check_required_create_fields($params);
    my $clean_params = $class->run_create_validators($params);

    # Create pool for this sprint
    my $start = datetime_from($clean_params->{start_date});
    my $end = datetime_from($clean_params->{end_date});
    my $team = Bugzilla::Extension::AgileTools::Team->check(
        {id => $clean_params->{team_id}});

    my $name = $team->name . " sprint ".$start->year."W".$start->week_number;
    if ($start->week_number != $end->week_number) {
        $name .= "-".$end->week_number;
    }
    Bugzilla->dbh->bz_start_transaction;
    my $pool = Bugzilla::Extension::AgileTools::Pool->create({name => $name});
    $clean_params->{id} = $pool->id;

    my $sprint = $class->insert_create_data($clean_params);
    # Set this as teams current sprint, if it doesn't have one yet
    if (! defined $team->current_sprint_id) {
        $team->set_current_sprint_id($sprint->id);
        $team->update();
    }
    Bugzilla->dbh->bz_commit_transaction;
    return $sprint;
}

# Object->insert_create_data does not work with non serial id on postgresql
sub insert_create_data {
    my ($class, $field_values) = @_;
    my $dbh = Bugzilla->dbh;

    my (@field_names, @values);
    while (my ($field, $value) = each %$field_values) {
        $class->_check_field($field, 'create');
        push(@field_names, $field);
        push(@values, $value);
    }

    my $qmarks = '?,' x @field_names;
    chop($qmarks);
    my $table = $class->DB_TABLE;
    $dbh->do("INSERT INTO $table (" . join(', ', @field_names)
             . ") VALUES ($qmarks)", undef, @values);

    my $object = $class->new($field_values->{id});

    Bugzilla::Hook::process('object_end_of_create', { class => $class,
                                                      object => $object });
    return $object;
}

sub update {
    my $self = shift;

    Bugzilla->dbh->bz_start_transaction;
    my($changes, $old) = $self->SUPER::update(@_);

    # Update pool name if the weeks have changed
    my $update_name = 0;
    my $start = datetime_from($self->start_date);
    my $end = datetime_from($self->end_date);

    if ($changes->{start_date}) {
        my $old = datetime_from($changes->{start_date}->[0]);
        $update_name = ($old->week_number != $start->week_number
                        || $old->year != $start->year);
    }
    if ($changes->{end_date}) {
        my $old = datetime_from($changes->{end_date}->[0]);
        $update_name = $update_name || (
                        $old->week_number != $end->week_number
                        || $old->year != $end->year);
    }
    if ($update_name) {
        my $name = $self->team->name." sprint ";
        $name .= $start->year."W".$start->week_number;
        if ($start->week_number != $end->week_number) {
            $name .= "-".$end->week_number;
        }
        $self->pool->set_all({name => $name});
        my $pool_changes = $self->pool->update();
        $changes->{name} = $pool_changes->{name};
    }
    Bugzilla->dbh->bz_commit_transaction;

    if (wantarray) {
        return ($changes, $old);
    }
    return $changes;
}

sub remove_from_db {
    my $self = shift;
    ThrowUserError("agile_permission_denied",
            {permission=>'delete active sprint'})
        if $self->is_active;
    # Take pool for later deletion
    my $pool = $self->pool;
    Bugzilla->dbh->bz_start_transaction;
    $self->SUPER::remove_from_db(@_);
    $pool->remove_from_db();
    Bugzilla->dbh->bz_commit_transaction;
}

sub TO_JSON {
    my $self = shift;
    # fetch the pool and name
    $self->name;
    # Determine current status
    $self->is_current;
    return { %{$self} };
}

=head1 METHODS

=over

=item C<is_current>

    Description: Returns true if sprint is teams current sprint

=cut

sub is_current {
    my $self = shift;
    $self->{is_current} ||= $self->id == $self->team->current_sprint_id;
    return $self->{is_current};
}

=item C<is_active>

    Description: Returns true if sprint is active

=cut

sub is_active {
    my $self = shift;
    return $self->pool->is_active;
}

=item C<close($params)>

    Description: Closes the sprint if it is teams current one

=cut

sub close {
    my ($self, $params) = @_;

    ThrowCodeError('params_required', {
            function => 'AgileTools::Sprint->close',
            params => ['next_id', 'start_date and end_date']})
        unless ($params->{next_id} ||
            ($params->{start_date} && $params->{end_date}));

    ThrowUserError('agile_sprint_close_not_current', {
            sprint => $self})
        unless $self->is_current;
    ThrowUserError('agile_sprint_close_uncommitted', {
            sprint => $self})
        unless $self->committed;

    my $archive = {
        team_id => $self->team_id,
        start_date => $self->start_date,
        end_date => $self->end_date,
        capacity => $self->capacity,
        committed => 1,
        items_on_commit => $self->items_on_commit,
        estimate_on_commit => $self->estimate_on_commit,
        effort_on_commit => $self->effort_on_commit,
        items_on_close => 0,
        resolved_on_close => 0,
        estimate_on_close => 0,
        effort_on_close => 0,
    };

    my @archive_bugs;
    for my $bug (sort {$a->pool_order - $b->pool_order} @{$self->pool->bugs}) {
        if (!$bug->isopened) {
            push(@archive_bugs, $bug);
            $archive->{resolved_on_close} += 1;
        }
        $archive->{items_on_close} += 1;
        $archive->{estimate_on_close} += $bug->remaining_time || 0;
        $archive->{effort_on_close} += $bug->actual_time || 0;
    }

    my $start_date = $params->{start_date};
    my $end_date = $params->{end_date};

    # If existing sprint is given, take bugs and date rage from that and
    # delete it.
    if ($params->{next_id}) {
        my $next_sprint = Bugzilla::Extension::AgileTools::Sprint->check(
            $params->{next_id});
        ThrowCodeError('agile_sprint_change_to_inactive')
            unless $next_sprint->pool->active;
        for my $bug (sort {$a->pool_order - $b->pool_order} @{$next_sprint->pool->bugs}) {
            $self->pool->add_bug($bug);
        }
        $start_date = $next_sprint->start_date;
        $end_date = $next_sprint->end_date;
        $next_sprint->remove_from_db;
    }
    $self->set_all({
            start_date => $start_date,
            end_date => $end_date,
            capacity => $params->{capacity} || 0,
        });
    $self->set('items_on_commit', 0);
    $self->set('estimate_on_commit', 0);
    $self->set('effort_on_commit', 0);
    $self->set('committed', 0);
    $self->update();

    my $archive_sprint = Bugzilla::Extension::AgileTools::Sprint->create($archive);
    for my $bug (@archive_bugs) {
        $archive_sprint->pool->add_bug($bug);
    }
    $archive_sprint->pool->set_is_active(0);
    $archive_sprint->pool->update;
    return $archive_sprint;
}

=item C<commit>

    Description: Commit to the sprint

=cut

sub commit {
    my $self = shift;
    return 0 if $self->committed;

    my $items = 0;
    my $estimate = 0;
    my $effort = 0;
    for my $bug (@{$self->pool->bugs}) {
        $items += 1 if $bug->isopened;
        $estimate += $bug->remaining_time || 0;
        $effort += $bug->actual_time || 0;
    }
    ThrowUserError('agile_sprint_commit_empty') unless $items;
    $self->set('items_on_commit', $items);
    $self->set('estimate_on_commit', $estimate);
    $self->set('effort_on_commit', $effort);
    $self->set('committed', 1);
    $self->update();
    return 1;
}

=item C<uncommit>

    Description: Revert the committed state of sprint

=cut

sub uncommit {
    my $self = shift;
    return 0 unless $self->committed;
    ThrowCodeError('agile_commit_closed_sprint') unless $self->is_active;
    $self->set('items_on_commit', 0);
    $self->set('estimate_on_commit', 0);
    $self->set('effort_on_commit', 0);
    $self->set('committed', 0);
    $self->update();
    return 1;
}


sub effort {
    my $self = shift;
    return unless $self->committed && !$self->is_active;
    return $self->effort_on_close - $self->effort_on_commit;
}

sub items_completion {
    my $self = shift;
    return unless $self->committed && !$self->is_active;
    if ($self->items_on_close) {
        return $self->resolved_on_close / $self->items_on_close * 100;
    }
}

sub effort_completion {
    my $self = shift;
    return unless $self->committed && !$self->is_active;
    my $total_on_close = $self->estimate_on_close + $self->effort;
    if ($total_on_close) {
        return $self->effort / $total_on_close * 100;
    }
}

1;

__END__

=back

=head1 SEE ALSO

L<Bugzilla::Object>

