package configurator::Controller::Config::Pf;
use HTTP::Status qw(:constants is_error);
use JSON;
use Moose;
use namespace::autoclean;
use Try::Tiny;

BEGIN { extends 'Catalyst::Controller'; }

=head1 NAME

configurator::Controller::Config::Pf - Catalyst Controller

=head1 DESCRIPTION

Catalyst Controller.

=head1 METHODS

=head2 index

=cut
sub index :Path :Args(0) {
    my ( $self, $c ) = @_;

    $c->visit('read', ['all'], ['read']);
}

=head2 object

Chained dispatch for a configuration parameter.

=cut
sub object :Chained('/') :PathPart('config/pf') :CaptureArgs(1) {
    my ($self, $c, $config_item) = @_;
    $c->stash->{config_item} = $config_item;
}

=head2 read

/config/pf/<section.param>/read

=cut
sub read :Chained('object') :PathPart('read') :Args(0) {
    my ($self, $c) = @_;
    my $config_item = $c->stash->{config_item};

    my ($status, $message) = $c->model('Config::Pf')->read($config_item);
    if (is_error($status)) {
        $c->res->status($status);
        $c->error($message);
    }
    else {
        $c->stash->{config} = $message;
    }
}

=head2 help 

/config/pf/<section.param>/help

Get help on a configuration parameter.

=cut
sub help :Chained('object') :PathPart('help') :Args(0) {
    my ($self, $c) = @_;
    my $config_item = $c->stash->{config_item};

    my ($status, $message) = $c->model('Config::Pf')->help($config_item);
    if (is_error($status)) {
        $c->res->status($status);
        $c->error($message);
    }
    else {
        $c->stash->{config} = $message;
    }
}

=head2 delete

/config/pf/<section.param>/delete

=cut
sub delete :Chained('object') :PathPart('delete') :Args(0) {
    my ($self, $c) = @_;
    my $config_item = $c->stash->{config_item};

    my ($status, $message) = $c->model('Config::Pf')->delete($config_item);
    if (is_error($status)) {
        $c->res->status($status);
        $c->error($message);
    }
    else {
        $c->stash->{status_msg} = $message;
    }
}

=head2 update

/config/pf/<section.param>/update

=cut
sub update :Chained('object') :PathPart('update') :Args(0) {
    my ($self, $c) = @_;
    my $config_item = $c->stash->{config_item};

    my $assignments_ref = $c->request->body_params->{assignments};

    if ($assignments_ref) {
        my $decoded_assignments_ref = try { return decode_json($assignments_ref); }
        catch {
            # Malformed JSON
            chomp $_;
            $c->res->status(HTTP_BAD_REQUEST);
            $c->stash->{status_msg} = $_;
            return;
        };
        if (defined($decoded_assignments_ref)) {
            my ($status, $message) = $c->model('Config::Pf')->update($config_item, $assignments_ref);
            if (is_error($status)) {
                $c->res->status($status);
                $c->error($message);
            }
            else {
                $c->res->status(HTTP_CREATED);
                $c->stash->{status_msg} = $message;
            }
        }
    }
    else {
        $c->res->status(HTTP_BAD_REQUEST);
        $c->stash->{status_msg} = 'Missing parameters';
    }
}

=head2 create

/config/pf/<section.param>/create

=cut

sub create :Chained('object') :PathPart('create') :Args(0) {
    my ($self, $c) = @_;
    my $config_item = $c->stash->{config_item};

    my $assignments_ref = $c->request->body_params;
    if (defined($assignments_ref)) {
        my ($status, $message) = $c->model('Config::Pf')->create($config_item, $assignments_ref);
        if (is_error($status)) {
            $c->res->status($status);
            $c->error($message);
        }
        else {
            $c->res->status(HTTP_CREATED);
            $c->stash->{status_msg} = $message;
        }
    }
    else {
        $c->res->status(HTTP_BAD_REQUEST);
        $c->stash->{status_msg} = 'Missing parameters';
    }
}

sub end : ActionClass('RenderView') {
    my ( $self, $c ) = @_;
    # TODO In DEVEL that's cool, but in production we want only a 500 generic message and logging on 'unhandled' errors
    if ( scalar @{ $c->error } ) {
        $c->stash->{status_msg} = $c->error;
        $c->forward('View::JSON');
        $c->error(0);
    }
    $c->forward('View::JSON');
}

=head1 AUTHOR

Olivier Bilodeau <obilodeau@inverse.ca>

=head1 COPYRIGHT

Copyright 2012 Inverse inc.

=head1 LICENSE

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301,
USA.

=cut

__PACKAGE__->meta->make_immutable;

1;
