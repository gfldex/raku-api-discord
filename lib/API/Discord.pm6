use API::Discord::Types;
use API::Discord::Connection;
use API::Discord::HTTPResource;

use API::Discord::Channel;
use API::Discord::Guild;
use API::Discord::Message;
use API::Discord::User;

use Cro::WebSocket::Client;
use Cro::WebSocket::Client::Connection;

unit class API::Discord is export;

=begin pod

=head1 NAME

API::Discord - Perl6 interface to L<Discord|https://discordapp.com> API

=head1 DESCRIPTION

This provides a lowish-level interface to the Discord API. It supplies a stream
of messages and other events to which your app can listen.

=head1 SYNOPSIS

    use API::Discord;

    my $d = API::Discord.new(:token(my-bot-token));

    await $d.connect;

    react {
        whenever $d.messages -> $m {
            ...
        }

        # Events not yet implemented
        #whenever $d.events -> $e {
        #    ...
        #}
    }

=head1 USING OBJECTS

API::Discord models the various API objects in corresponding classes. These
classes can either be used directly, or used via the API object. The API object
has the advantage of also having connections to Discord, thus allowing you to
fetch and send data without doing it manually.

Most of the time, you will want to use an existing object to create and send
another object.

For example, Discord communicates with us which Guilds and Channels we are in,
so the API constantly keeps a cache of these, since they are usually few and
rarely change. Therefore, to create a Channel, you might do it via Guild, and to
send a Message, you might do it via Channel.

Channel and Guild are usually your entrypoints to doing things.

    $api.get-channel($id).send-message("Hi I'm a bot");
    $api.get-guild($id).create-channel({ ... });

The other entrypoint to information are the message and event supplies. These
emit complete objects, which can be used to perform further actions. For
example, the Message class stores the Channel from which it came, and Channel
has send-message:

    whenever $api.messages -> $m {
        $m.channel.send-message("I heard that!");
    }

All of these classes use the API to fetch and send if they need to. This
prevents them from having to know about one another, which would result in
circular dependencies. It also makes them easier to test N<If we ever did that>.

Ultimately, you can always just create and send an object to Discord if you want
to do it that way.

    my $m = API::Discord::Message.new(...);
    $api.send($m);

This requires you to know all the parts you need for the operation to be
successful, however.

=head2 CRUD

The core of the Discord API is simple CRUD mechanics over REST. The general idea
in API::Discord is that if an object has an ID, then C<send> will update it;
otherwise, it will create it and populate the ID from the response.

This way, the same few methods handle most of the interaction you will have with
Discord: editing a message is done by calling C<send> with a Message object that
already has an ID; whereas posting a new message would simply be calling C<send>
with a message with no ID, but of course a channel ID instead.

API::Discord also handles deflating your objects into JSON. The structures
defined by the Discord docs are supported recursively, which means if you set an
object on another object, the inner object will also be deflated—into the
correct JSON property—to be sent along with the outer object. However, if the
Discord API doesn't support that structure in a particular situation, it just
won't try to do it.

For example, you can set an Embed on a Message and just send the Message, and
this will serialise the Embed and send that too.

    my $m = API::Discord::Message.new(:channel($channel));
    $m.embed(...);

    API::Discord.send($m);

This example will serialise the Message and the Embed and send them, but will
not attempt to serialise the entire Channel object into the Message object
because that is not supported. Instead, it will take the channel ID from the
Channel object and put that in the expected place.

Naturally, one cannot delete an object with no ID, just as one cannot attempt to
read an object given anything but an ID. (Searching notwithstanding.)

=head1 PROPERTIES

=end pod

has Connection $!conn;

#| The API version to use. Defaults to 6 but can be overridden if the API moves on without us.
has Int $.version = 6;
#| Host to which to connect. Can be overridden for testing e.g.
has Str $.host = 'gateway.discord.gg';
#| Bot token or whatever, used for auth.
has Str $.token is required;

# Docs say, increment number each time, per process
has Int $!snowflake = 0;

has Supplier $!messages = Supplier.new;

has Supplier $!events = Supplier.new;

#| A hash of Channel objects, keyed by the Channel ID.
has %.channels;

#| A hash of Guild objects that the user is a member of, keyed by the Guild ID. B<TODO> Currently this is not populated.
has %.guilds;

method !start-message-tap {
    $!conn.messages.tap( -> $message {
        self!handle-message($message);
        $!messages.emit($message);
    })
}

method !handle-message($message) {
    if $message<d><channels> {
        for $message<d><channels>.values -> $c {
            %.channels{$c<id>} = self.create-channel($c);
        }
    }
    else { $message.say }
}

submethod DESTROY {
    $!conn.close;
}

#| Connects to discord. Await the returned Promise, then tap $.messages and $.events
method connect($session-id?, $sequence?) returns Promise {
    $!conn = Connection.new(
        url => "wss://{$.host}/?v={$.version}&encoding=json",
        token => $.token,
      |(:$session-id if $session-id),
      |(:$sequence if $sequence),
    );

    return $!conn.opener.then({ self!start-message-tap; $!conn.closer });
}

#| Emits a Message object whenever a message is received. B<TODO> Currently this emits hashes.
method messages returns Supply {
    $!messages.Supply;
}
#| A Supplier that emits things that aren't messages. B<TODO> Implement this
method events returns Supply {
    $!events.Supply;
}

#| Creates an integer using the snowflake algorithm, guaranteed unique probably.
method generate-snowflake {
    my $time = DateTime.now - DateTime.new(year => 2015);
    my $worker = 0;
    my $proc = 0;
    my $s = $!snowflake++;

    return ($time.Int +< 22) + ($worker +< 17) + ($proc +< 12) + $s;
}

# Create/update
#| Sends an object to Discord B<TODO>
method send (JSONy $object) returns Promise {}

# Delete
#| Deletes the object B<TODO>
method delete (JSONy $object) returns Promise {}

# Read
#| Fetches the object by ID, given a type object B<TODO>
method fetch (API::Discord::Object:U, $id) returns API::Discord::Object {}

# get-* will fetch
# create-* will construct

#| Returns a single Message object by ID, fetching if necessary.
method get-message ($id) returns Message {}

#| Returns an array of Message objects from their IDs. Fetches as necessary.
method get-messages (@message-ids) returns Array[Message] {
}

#| Returns a Message object from a JSON-shaped hash.
method create-message (%json) returns Message {
    API::Discord::Message.from-json(%json);
}

#| Returns a single Channel object by ID, fetching if necessary.
method get-channel ($id) returns Channel {}

#| Returns an array of Channel objects from their IDs. Fetches as necessary.
method get-channels (@channel-ids) returns Array[Channel] {
}

#| Returns a Channel object from a JSON-shaped hash.
method create-channel (%json) returns API::Discord::Channel {
    API::Discord::Channel.from-json(%json);
}

#| Returns a single Guild object by ID, fetching if necessary.
method get-guild ($id) returns Guild {}

#| Returns an array of Guild objects from their IDs. Fetches as necessary.
method get-guilds (@guild-ids) returns Array[Guild] {
}

#| Returns a Guild object from a JSON-shaped hash.
method create-guild (%json) returns Guild {
}
