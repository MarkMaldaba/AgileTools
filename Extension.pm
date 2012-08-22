# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the AgileTools Bugzilla Extension.
#
# The Initial Developer of the Original Code is Pami Ketolainen
# Portions created by the Initial Developer are Copyright (C) 2012 the
# Initial Developer. All Rights Reserved.
#
# Contributor(s):
#   Pami Ketolainen <pami.ketolainen@gmail.com>

package Bugzilla::Extension::AgileTools;
use strict;
use base qw(Bugzilla::Extension);

use Bugzilla::Error;
use Bugzilla::Constants;
use Bugzilla::Field;


use Bugzilla::Extension::AgileTools::Constants;
use Bugzilla::Extension::AgileTools::Pool;
use Bugzilla::Extension::AgileTools::Role;
use Bugzilla::Extension::AgileTools::Team;
use Bugzilla::Extension::AgileTools::Util;
use Bugzilla::Extension::AgileTools::Burn;

use JSON;

use Data::Dumper;

our $VERSION = '0.01';

my %template_handlers;
my %page_handlers;

# Helper to add a handler for the given template.
sub _add_template_handler {
    my ($name, $sub) = @_;
    push @{$template_handlers{$name} ||= []}, $sub;
}

# Helper to add a handler for the given page.
sub _add_page_handler {
    my ($name, $sub) = @_;
    push @{$page_handlers{$name} ||= []}, $sub;
}

###############
# Page handlers
###############

_add_page_handler("agiletools/team/list.html", sub {
    my ($vars) = @_;
    my $cgi = Bugzilla->cgi;
    my $action = $cgi->param("action") || "";
    if ($action eq "remove") {
        ThrowUserError("agile_team_manage_denied")
            unless user_can_manage_teams;
        my $team = Bugzilla::Extension::AgileTools::Team->check({
                id => $cgi->param("team_id")});
        $vars->{team} = {name=>$team->name};
        $team->remove_from_db();
        $vars->{message} = "agile_team_removed";
    }
    $vars->{agile_teams} = Bugzilla::Extension::AgileTools::Team->match();
    $vars->{can_manage_teams} = user_can_manage_teams();
});

_add_page_handler("agiletools/team/show.html", sub {
    my ($vars) = @_;

    my $cgi = Bugzilla->cgi;
    my $team;
    my $action = $cgi->param("action") || "";
    if ($action eq "create") {
        ThrowUserError("agile_team_manage_denied")
            unless user_can_manage_teams;
        $team = Bugzilla::Extension::AgileTools::Team->create({
                name => $cgi->param("name"),
                process_id => $cgi->param("process_id"),
            });
        $vars->{message} = "agile_team_created";
    } else {
        my $id = $cgi->param("team_id");
        $team = Bugzilla::Extension::AgileTools::Team->check({id => $id});
    }

    $vars->{processes} = AGILE_PROCESS_NAMES;
    $vars->{team} = $team;
    $vars->{roles} = Bugzilla::Extension::AgileTools::Role->match();

    # TODO these values are probably cached already
    $vars->{keywords} = Bugzilla::Keyword->match();
    my @components;
    foreach my $product (Bugzilla::Product->get_all()) {
        next unless Bugzilla->user->can_see_product($product->name);
        foreach my $component (@{$product->components}) {
            push(@components, {
                    id => $component->id,
                    name => $product->name . " : " . $component->name,
                });
        }
    }
    $vars->{components} = \@components;
    $team->roles;
    $team->components;
    $team->keywords;
    $vars->{team_json} = JSON->new->utf8->convert_blessed->encode($team);
});

_add_page_handler("agiletools/team/create.html", sub {
    my ($vars) = @_;
    $vars->{processes} = AGILE_PROCESS_NAMES;
});

_add_page_handler("agiletools/scrum/planning.html", sub {
    my ($vars) = @_;
    my $id = Bugzilla->cgi->param("team_id");
    ThrowUserError("invalid_parameter",
        {name=>"team_id", err => "Not specified"})
            unless defined $id;
    my $team = get_team($id);
    $team->pools;
    $vars->{team} = $team;
});

_add_page_handler("agiletools/scrum/sprints.html", sub {
    my ($vars) = @_;
    my $id = Bugzilla->cgi->param("team_id");
    ThrowUserError("invalid_parameter",
        {name=>"team_id", err => "Not specified"})
            unless defined $id;
    my $team = get_team($id);
    my @sprints = reverse @{Bugzilla::Extension::AgileTools::Sprint->match(
            {team_id => $team->id})};
    $vars->{team} = $team;
    $vars->{sprints} = \@sprints;
});

_add_page_handler("agiletools/user_summary.html", sub {
    my ($vars) = @_;
    $vars->{processes} = AGILE_PROCESS_NAMES;
    $vars->{agile_teams} = Bugzilla->user->agile_teams;
});

_add_template_handler('list/burnchart.html.tmpl', sub {
    my ($vars) = @_;
    my $cgi = Bugzilla->cgi;
    my @bug_ids = map {$_->{bug_id}} @{$vars->{bugs}};
    my $start = $cgi->param("burn_start");
    my $end = $cgi->param("burn_end");
    my $data = get_burndata(\@bug_ids, $start, $end);
    $vars->{burn_json} = JSON->new->utf8->encode($data);
});

#######################################
# Page and template processing handlers
#######################################

sub page_before_template {
    my ($self, $params) = @_;
    my $page_id = $params->{page_id};
    if ($page_id =~ /^agiletools\//) {
        ThrowUserError("agile_access_denied")
            unless Bugzilla->user->in_group(AGILE_USERS_GROUP);
    }

    my $subs = $page_handlers{$page_id};
    for my $sub (@{$subs || []}) {
        $sub->($params->{vars});
    }
}

sub template_before_process {
    my ($self, $params) = @_;

    my $subs = $template_handlers{$params->{file}};
    for my $sub (@{$subs || []}) {
        $sub->($params->{vars});
    }
}

#############################
# BayotBase page header links
#############################

sub bb_common_links {
    my ($self, $args) = @_;
    return unless Bugzilla->user->in_group(AGILE_USERS_GROUP);
    $args->{links}->{agile_teams} = [
        {
            text => "All teams",
            href => "page.cgi?id=agiletools/team/list.html",
            priority => 11
        }
    ];
    $args->{links}->{agile_summary} = [
        {
            text => "My teams",
            href => "page.cgi?id=agiletools/user_summary.html",
            priority => 10
        }
    ];
}

############################
# Additional buglist columns
############################

sub buglist_columns {
    my ($self, $args) = @_;
    my $columns = $args->{columns};
    $columns->{"agile_pool.name"} = {
        name => "COALESCE(agile_pool.name,'')",
        title => "Pool" };
    $columns->{"bug_agile_pool.pool_order"} = {
        name => "COALESCE(bug_agile_pool.pool_order, -1)",
        title => "Pool order" };
    $columns->{"bug_agile_pool.pool_id"} = {
        name => "COALESCE(bug_agile_pool.pool_id, -1)",
        title => "Pool ID" };
}

#################################################
# Table joins required for the additional columns
#################################################

sub buglist_column_joins {
    my ($self, $args) = @_;
    my $joins = $args->{column_joins};
    $joins->{"agile_pool.name"} = {
        table => "bug_agile_pool",
        as => "bug_agile_pool",
        then_to => {
            as => "agile_pool",
            table => "agile_pool",
            from => "bug_agile_pool.pool_id",
            to => "id",
        },
    };
    $joins->{"bug_agile_pool.pool_order"} = {
        table => "bug_agile_pool",
        as => "bug_agile_pool",
    };
    $joins->{"bug_agile_pool.pool_id"} = {
        table => "bug_agile_pool",
        as => "bug_agile_pool",
    };
}

#########################################
# Additional opretions when updating bugs
#########################################

sub bug_end_of_update {
    my ($self, $args) = @_;

    my ($bug, $changes) = @$args{qw(bug changes)};

    if (my $status_change = $changes->{'bug_status'}) {
        my $old_status = new Bugzilla::Status({ name => $status_change->[0] });
        my $new_status = new Bugzilla::Status({ name => $status_change->[1] });
        if (!$new_status->is_open && $old_status->is_open) {
            # Bug is being closed

            # Check that actual time is set if it is required for the severity and resolution
            my $check_severity = grep {$bug->bug_severity eq $_}
                    @{Bugzilla->params->{"agile_check_time_severity"}};
            my $check_resolution = grep {$bug->resolution eq $_}
                    @{Bugzilla->params->{"agile_check_time_resolution"}};
            if ($check_severity && $check_resolution) {
                ThrowUserError("agile_actual_time_required")
                    if ($bug->actual_time == 0);
            }

            # Remove closed bug from any backlog
            my $blids = Bugzilla->dbh->selectcol_arrayref(
                'SELECT backlog_id FROM agile_team');
            if (grep ($bug->pool->id == $_, @$blids)){
                $bug->pool->remove_bug($bug->id);
                delete $bug->{pool};
                delete $bug->{pool_id};
            }

        }
    }
}

sub object_end_of_update {
    my ($self, $args) = @_;
    my ($obj, $old_obj, $changes) = @$args{qw(object old_object changes)};

    if ($obj->isa("Bugzilla::Bug")) {
        # Update remaining time if estimated time is changed
        if (defined $changes->{estimated_time} &&
            ! defined $changes->{remaining_time})
        {
            my ($old, $new) = @{$changes->{estimated_time}};
            if ($obj->{remaining_time} != $new)
            {
                Bugzilla->dbh->do("UPDATE bugs ".
                                     "SET remaining_time = ? ".
                                   "WHERE bug_id = ?",
                        undef, $new, $obj->id);
                $changes->{remaining_time} = [$old_obj->{remaining_time}, $new];
            }
        }
    }
}


##########################################
# Database updates performed in checksetup
##########################################

sub install_update_db {
    my ($self, $args) = @_;
    # Make sure agiletools user group exists
    if (!defined Bugzilla::Group->new({name => AGILE_USERS_GROUP})) {
        Bugzilla::Group->create(
            {
                name => AGILE_USERS_GROUP,
                description => "Users allowed to use AgileTools",
                userregexp => ".*",
            }
        );
    }
    # Create initial team member roles
    if (!Bugzilla::Extension::AgileTools::Role->any_exist()) {
        Bugzilla::Extension::AgileTools::Role->create(
            {
                name => "Product Owner",
                custom => 0,
                can_edit_team => 1,
            }
        );
        Bugzilla::Extension::AgileTools::Role->create(
            {
                name => "Scrum Master",
                custom => 0,
                can_edit_team => 1,
            }
        );
    }
    # Create pool field definitions
    if (!defined Bugzilla::Field->new({name=>"agile_pool.name"})) {
        Bugzilla::Field->create(
            {
                name => "agile_pool.name",
                description => "Pool",
                buglist => 1,
            }
        );
    }
    if (!defined Bugzilla::Field->new({name=>"bug_agile_pool.pool_order"})) {
        Bugzilla::Field->create(
            {
                name => "bug_agile_pool.pool_order",
                description => "Pool Order",
                is_numeric => 1,
                buglist => 1,
            }
        );
    }
    if (!defined Bugzilla::Field->new({name=>"bug_agile_pool.pool_id"})) {
        Bugzilla::Field->create(
            {
                name => "bug_agile_pool.pool_id",
                description => "Pool ID",
                is_numeric => 1,
                buglist => 1,
            }
        );
    }
}

################################################
# Search operators for the additional bug fields
################################################

sub search_operator_field_override {
    my ($self, $args) = @_;
    my $operators = $args->{'operators'};
    my $search = $args->{'search'};

    $operators->{'agile_pool.name'}->{_default} = sub {
        _add_agile_pool_join($search, @_)
    };
    $operators->{'bug_agile_pool.pool_order'}->{_default} = sub {
        _add_bug_agile_pool_join($search, @_)
    };
    $operators->{'bug_agile_pool.pool_id'}->{_default} = sub {
        _add_bug_agile_pool_join($search, @_)
    };
}

# Table join required for Pool name
sub _add_agile_pool_join {
    my $search = shift;
    my ($invocant, $args) = @_;
    my ($joins) = @$args{qw(joins)};
    if(! grep $_->{table} eq 'bug_agile_pool', @$joins) {
        my $join = {
            table => "bug_agile_pool",
            as => "bug_agile_pool",
            then_to => {
                table => "agile_pool",
                as => "agile_pool",
                from => "bug_agile_pool.pool_id",
                to => "id",
            },
        };
        push(@$joins, $join);
    }
    $args->{full_field} = "COALESCE($args->{full_field}, '')";
    $search->_do_operator_function($args);
}

# Table join required for Pool id and order
sub _add_bug_agile_pool_join {
    my $search = shift;
    my ($invocant, $args) = @_;
    my ($joins) = @$args{qw(joins)};
    if(! grep $_->{table} eq 'bug_agile_pool', @$joins) {
        my $join = {
            table => "bug_agile_pool",
            as => "bug_agile_pool",
        };
        push(@$joins, $join);
    }
    $args->{full_field} = "COALESCE($args->{full_field}, -1)";
    $search->_do_operator_function($args);
}

#################
# Database schema
#################

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    my $schema = $args->{schema};

    # Team information
    $schema->{agile_team} = {
        FIELDS => [
            id => {
                TYPE => 'MEDIUMSERIAL',
                NOTNULL => 1,
                PRIMARYKEY => 1,
            },
            name => {
                TYPE => 'varchar(64)',
                NOTNULL => 1,
            },
            group_id => {
                TYPE => 'INT3',
                REFERENCES => {
                    TABLE => 'groups',
                    COLUMN => 'id',
                },
            },
            process_id => {
                TYPE => 'INT1',
                NOTNULL => 1,
                DEFAULT => 1,
            },
            backlog_id => {
                TYPE => 'INT3',
                NOTNULL => 0,
                REFERENCES => {
                    TABLE => 'agile_pool',
                    COLUMN => 'id',
                    DELETE => 'SET NULL',
                },
            },
        ],
        INDEXES => [
            agile_team_name_idx => {
                FIELDS => ['name'],
                TYPE => 'UNIQUE',
            },
            agile_team_group_id_idx => ['group_id'],
        ],
    };

    # Team component responsibilities
    $schema->{agile_team_component} = {
        FIELDS => [
            team_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'agile_team',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            component_id => {
                TYPE => 'INT2',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'components',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
        ],
        INDEXES => [
            agile_team_component_unique_idx => {
                FIELDS => ['team_id', 'component_id'],
                TYPE => 'UNIQUE',
            },
            agile_team_component_team_id_idx => ['team_id'],
        ],
    };

    # Team keyword responsibilities
    $schema->{agile_team_keyword} = {
        FIELDS => [
            team_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'agile_team',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            keyword_id => {
                TYPE => 'INT2',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'keyworddefs',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
        ],
        INDEXES => [
            agile_team_keyword_unique_idx => {
                FIELDS => ['team_id', 'keyword_id'],
                TYPE => 'UNIQUE',
            },
            agile_team_keyword_team_id_idx => ['team_id'],
        ],
    };

    # User role definitions
    $schema->{agile_role} = {
        FIELDS => [
            id => {
                TYPE => 'SMALLSERIAL',
                NOTNULL => 1,
                PRIMARYKEY => 1,
            },
            name => {
                TYPE => 'varchar(64)',
                NOTNULL => 1,
            },
            custom => {
                TYPE => 'BOOLEAN',
                NOTNULL => 1,
                DEFAULT => 'TRUE',
            },
            can_edit_team => {
                TYPE => 'BOOLEAN',
                NOTNULL => 1,
                DEFAULT => 'FALSE',
            }
        ],
        INDEXES => [
            'agile_role_name_idx' => {
                FIELDS => ['name'],
                TYPE => 'UNIQUE',
            }
        ],
    };

    # Team - user - role mapping
    $schema->{agile_user_role} = {
        FIELDS => [
            team_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'agile_team',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            user_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'profiles',
                    COLUMN => 'userid',
                    DELETE => 'CASCADE',
                },
            },
            role_id => {
                TYPE => 'INT2',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'agile_role',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
        ],
        INDEXES => [
            agile_user_role_unique_idx => {
                FIELDS => [qw(team_id user_id role_id)],
                TYPE   => 'UNIQUE',
            },
            agile_user_role_user_idx => ['user_id'],
        ],
    };

    # Bug pool
    $schema->{agile_pool} = {
        FIELDS => [
            id => {
                TYPE => 'MEDIUMSERIAL',
                NOTNULL => 1,
                PRIMARYKEY => 1,
            },
            name => {
                TYPE => 'varchar(64)',
                NOTNULL => 1,
            },
        ],
    };

    # Bug - Pool mapping with bug ordering
    $schema->{bug_agile_pool} = {
        FIELDS => [
            bug_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                PRIMARYKEY => 1,
                REFERENCES => {
                    TABLE => 'bugs',
                    COLUMN => 'bug_id',
                    DELETE => 'CASCADE',
                },
            },
            pool_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'agile_pool',
                    COLUMN => 'id',
                    DELETE => 'CASCADE',
                },
            },
            pool_order => {
                TYPE => 'INT3',
            },

        ],
        INDEXES => [
            agile_bug_pool_pool_idx => ['pool_id'],
        ],
    };

    # Scrum Sprint
    $schema->{agile_sprint} = {
        FIELDS => [
            id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                PRIMARYKEY => 1,
                REFERENCES => {
                    TABLE => 'agile_pool',
                    COLUMN => 'id',
                },
            },
            start_date => {
                TYPE => 'DATETIME',
                NOTNULL => 1,
            },
            end_date => {
                TYPE => 'DATETIME',
                NOTNULL => 1,
            },
            team_id => {
                TYPE => 'INT3',
                NOTNULL => 1,
                REFERENCES => {
                    TABLE => 'agile_team',
                    COLUMN => 'id',
                },
            },
            capacity => {
                TYPE => 'decimal(7,2)',
                NOTNULL => 1,
                DEFAULT => 0,
            },
        ],
        INDEXES => [
        ],
    };
}

sub _get_bad_pools {
    my $dbh = Bugzilla->dbh;

    my $pool_ids = $dbh->selectcol_arrayref(
        'SELECT id FROM agile_pool');

    my $sth = $dbh->prepare(
        'SELECT pool_order FROM bug_agile_pool WHERE pool_id = ? '.
        'ORDER BY pool_order ASC');

    my %bad_pools ;
    for my $pool_id (@$pool_ids) {
        $sth->execute($pool_id);
        my $expected = 1;
        my @gaps;
        while (my ($real) = $sth->fetchrow_array) {
            if ($real != $expected) {
                push(@gaps, {start=> $expected, end=> $real});
                $expected = $real + 1;
            } else {
                $expected += 1;
            }
        }
        if (@gaps) {
            $bad_pools{$pool_id} = \@gaps;
        }
    }
    return \%bad_pools;
}

sub sanitycheck_repair {
    my ($self, $args) = @_;

    my $cgi = Bugzilla->cgi;
    my $dbh = Bugzilla->dbh;
    my $status = $args->{'status'};
    if ($cgi->param('agiletools_repair_pool_order')) {
        $status->('agiletools_repair_pool_order_start');

        my $fix_gap = $dbh->prepare(
            'UPDATE bug_agile_pool '.
            'SET pool_order = pool_order - ? '.
            'WHERE pool_id = ? AND pool_order > ?');
        my $get_dupes = $dbh->prepare(
            'SELECT bug_id FROM bug_agile_pool '.
            'WHERE pool_id = ? AND pool_order = ?');
        my $make_room = $dbh->prepare(
            'UPDATE bug_agile_pool '.
            'SET pool_order = pool_order + ? '.
            'WHERE pool_id = ? AND pool_order > ?');
        my $fix_dupe = $dbh->prepare(
            'UPDATE bug_agile_pool '.
            'SET pool_order = pool_order + ? '.
            'WHERE pool_id = ? AND bug_id = ?');

        my $bad_pools = _get_bad_pools();
        for my $pool_id (keys %$bad_pools){
            for my $gap (reverse @{$bad_pools->{$pool_id}}) {
                my $change = $gap->{end} - $gap->{start};
                if ($change > 0) {
                    $fix_gap->execute($change, $pool_id, $gap->{start});
                } elsif ($change = -1) {
                    # Duplicate values
                    $get_dupes->execute($pool_id, $gap->{end});
                    my @dupes = map {$_->[0]} @{$get_dupes->fetchall_arrayref};
                    shift @dupes;
                    $make_room->execute(scalar @dupes, $pool_id, $gap->{end});
                    $change = 1;
                    for my $bug_id (@dupes) {
                        $fix_dupe->execute($change, $pool_id, $bug_id);
                    }
                } else {
                    $status->('agiletools_repair_pool_order_weird_alert',
                        {pool => $pool_id, gap=> $gap}, 'alert');
                }
            }
        }
        $status->('agiletools_repair_pool_order_end');
    }
}

sub sanitycheck_check {
    my ($self, $args) = @_;
    my $status = $args->{'status'};

    $status->('agiletools_check_pool_order');
    my $bad_pools = _get_bad_pools();
    if (%$bad_pools) {
        $status->('agiletools_check_pool_order_alert',
            {pools => $bad_pools}, 'alert');
        $status->('agiletools_chek_pool_order_prompt');
    }
}

#####################
# Webservice bindings
#####################

sub webservice {
    my ($self, $args) = @_;
    $args->{dispatch}->{'Agile'} =
        "Bugzilla::Extension::AgileTools::WebService";
    $args->{dispatch}->{'Agile.Team'} =
        "Bugzilla::Extension::AgileTools::WebService::Team";
    $args->{dispatch}->{'Agile.Sprint'} =
        "Bugzilla::Extension::AgileTools::WebService::Sprint";
    $args->{dispatch}->{'Agile.Pool'} =
        "Bugzilla::Extension::AgileTools::WebService::Pool";
}

########################
# Admin interface panels
########################

sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{panel_modules};
    $modules->{AgileTools} = "Bugzilla::Extension::AgileTools::Params";
}

__PACKAGE__->NAME;
