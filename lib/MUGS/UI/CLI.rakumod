# ABSTRACT: CLI UI for MUGS, including App and game UIs

unit module MUGS::UI::CLI:auth<zef:japhb>:ver<0.1.2>;

use Terminal::LineEditor::RawTerminalInput;

use MUGS::Core;
use MUGS::Client;
use MUGS::UI;
use MUGS::Util::StructureValidator;


# Sentinel to request this game UI should quit its play loop
class Sentinel::QUIT { }


# Base class for CLIs
class Game is MUGS::UI::Game {
    has Terminal::LineEditor::CLIInput:D $.input  .= new;
    has Channel:D                        $.pushed .= new;
    has Bool $.screen-reader;  #= Tune output for screen readers

    method ui-type()       { 'CLI' }
    method prompt-string() { '> '  }
    method is-lobby()      { False }
    method game-help()     { ...   }

    method activate() {
        my $message  = do if $.screen-reader {
            "Activating $.game-type.uc()"
            ~ (" game ID $.client.game-id()" unless $.is-lobby)
            ~ ".";
        }
        else {
            "--- $.game-type.uc()"
            ~ (" (GAME $.client.game-id())" unless $.is-lobby)
            ~ " ----------\n";
        }
        $.app-ui.put-sanitized($message);
    }

    method shutdown() {
        $.app-ui.put-sanitized("Leaving $.game-type.uc()"
                               ~ (" game ID $.client.game-id()" unless $.is-lobby)
                               ~ ".")
            if $.screen-reader;
    }

    method handle-server-message(MUGS::Message::Push:D $message) {
        $.pushed.send($message);
    }

    method process-pushed-messages() {
        while $.pushed.poll -> $message {
            self.process-push-message($message);
        }
    }

    method process-push-message(MUGS::Message::Push:D $message) {
        given $message.type {
            when 'game-update' {
                self.show-game-state($message);
            }
            when 'game-event' {
                constant %schema = {
                    event => {
                        character-name => Str but Optional,
                        event-type     => GameEventType(Int),
                    }
                };

                my $validated      = $message.validated-data(%schema)<event>;
                my $event-type     = GameEventType($validated<event-type>);
                my $character-name = $validated<character-name> // 'unknown';

                if self.is-lobby {
                    self.show-initial-state if $event-type == GameStarted;
                    return;
                }

                given $event-type {
                    when CharacterJoined {
                        $.app-ui.put-sanitized("'$character-name' has joined.");
                    }
                    when CharacterLeft {
                        $.app-ui.put-sanitized("'$character-name' has left.");
                    }
                    when GameStarted {
                        $.app-ui.put-sanitized("$.game-type game $.client.game-id() started.");
                        self.show-initial-state;
                    }
                }
            }
            when 'message' {
                constant %schema = message-type => Str,
                                   message      => Str,
                                   sender       => Str;
                my $data   = $message.validated-data(%schema);
                my $text   = $.app-ui.sanitize-text($data<message>);
                my $sender = $.app-ui.sanitize-text($data<sender>);

                given $data<message-type> {
                    # XXXX: Color coding friends or admins?
                    when 'direct-message' {
                        put "DM: <$sender> $text";
                    }
                    when 'broadcast' {
                        put "<$sender> $text";
                    }
                    default {
                        die "Unknown push message type!";
                    }
                }
            }
            default {
                !!! "Push message type '$_' not yet implemented.";
            }
        }
    }

    method filter-games(@games, Bool :$all) {
        $all ?? @games !! @games.grep: { MUGS::UI.ui-exists($.ui-type, .<game-type>) }
    }

    method available-game-types(::?CLASS:D: Bool :$all) {
        self.filter-games($.client.available-game-types, :$all)
    }

    method active-games(::?CLASS:D: Bool :$all) {
        self.filter-games($.client.active-games, :$all)
    }

    method switch-to-game($game-id) {
        if $game-id && $.client.session.games{$game-id} {
            if $game-id eq $.client.game-id {
                $.app-ui.put-sanitized("Already in game '$game-id'; use `/games` to see a list.");
            }
            else {
                $.app-ui.switch-to-game-ui(:$game-id);
            }
        }
        elsif $game-id -> GameID() $game-id {
            my $game = self.active-games.first(*<game-id> eq $game-id);
            with $game {
                my $game-type = .<game-type>;
                $.app-ui.put-status-update("Joining $game-type game '$game-id'");
                my $client = $.app-ui.new-game-client(:$game-type, :$game-id);
                $.app-ui.launch-game-ui(:$game-type, :$client)
            }
            else {
                $.app-ui.put-sanitized("No such game ID '$game-id'; use `/games` to see a list.");
            }
        }
        else {
            put 'Must specify a game ID; use `/games` to see a list.';
        }
    }

    method show-games() {
        # XXXX: What about games for same user in different sessions?
        my @games    = $.client.session.games.values.sort:
                           { $^a.game-type cmp $^b.game-type ||
                             $^a.game-id   <=> $^b.game-id   };
        my $max-id   = max 2, @games.map(*.game-id.chars).max;
        my $max-type = max 4, @games.map(*.game-type.chars).max;
        my $format   = "  %s %{$max-id}s   %-{$max-type}s   %s\n";

        printf $format, ' ', 'ID', 'TYPE', 'CHARACTER';
        for @games {
            printf $format, ($_ === $.client ?? '*' !! ' '), .game-id, .game-type,
                                                             .character-name;
        }

        put '';
    }

    method not-started-help() {
        q:to/HELP/;
            Your game has not started yet (perhaps waiting for additional players).
            Once the game starts, you'll be able to play as follows:
            HELP
    }

    method general-help() {
        q:to/HELP/;
            You may also get help for advanced commands with `/help`
            or exit a MUGS game by pressing Ctrl-C.
            HELP
    }

    method show-game-help() {
        put self.not-started-help if $.client.gamestate == NotStarted;
        put self.game-help;
        put '';
        put self.general-help;
    }

    method show-slash-help($topic) {
        put q:to/HELP/;
        GENERAL
            /help       Show this help text
            /status     Show current status

        MANAGING GAMES
            /game <id>  Switch to game <id>
            /games      Show all active games
            /leave      Leave current game
            /lobby      Switch to game lobby, leaving current game running

        MESSAGES
            /say <message>              Send <message> to general game-wide chat
            /msg <character> <message>  Send <message> directly to <character>
        HELP
    }

    method show-slash-say-help() {
        print q:to/HELP/;
            Must include a message to send:
                /say <message>
            HELP
    }

    method show-slash-msg-help() {
        print q:to/HELP/;
            Must specify both a character and a message:
                /msg <character> <message>
            (Quote the character name if it contains whitespace.)
            HELP
    }

    method show-status() {
        my $session   = $.client.session;
        my $server    = $session.server ~~ Str ?? $session.server !! '<local server>';
        my $num-games = $session.games.elems;

        $.app-ui.put-sanitized: qq:to/STATUS/;
            SESSION
                Server:             $server
                Logged in as:       $session.username()
                Default persona:    $session.default-persona()
                Default character:  $session.default-character()
                Active games:       $num-games (use `/games` to view)
            STATUS
    }

    method say-to-game(Str $message) {
        $message ?? $.client.broadcast-message-to-game(:$message)
                 !! self.show-slash-say-help;
    }

    method message-character($rest) {
        # XXXX: Trying to figure out how to get abstracted <( )> to work
        # my token quoted-arg {
        #                     | \' <( <-[']>+ )> \'
        #                     | \" <( <-["]>+ )> \"
        #                     }  # "
        # my token arg        { <quoted-arg> | <!before <['"]>> \S+ }
        # my token last-arg   { <quoted-arg> | .+ }

        my token last-arg   { \' <( <-[']>+ )> \' | \" <( <-["]>+ )> \" | .+ };  # "
        my token arg        { \' <( <-[']>+ )> \' | \" <( <-["]>+ )> \"          # "
                              | <!before <['"]> > \S+ };

        if $rest ~~ Str:D && $rest ~~ /^ <char=arg> \s+ <msg=last-arg> $/ {
            $.client.send-message-to-character(:character(~$<char>), :message(~$<msg>));
        }
        else {
            self.show-slash-msg-help;
        }
    }

    method handle-leave() {
        self.is-lobby ?? $.app-ui.leave-current-ui
                      !! await $.client.leave;
    }

    method handle-slash-command($command) {
        my ($slash, $rest) = $command.split(/\s+/, 2);
        given $slash.lc {
            # General commands
            when '/help'   { self.show-slash-help($rest) }
            when '/status' { self.show-status }

            # Game management
            when '/game'   { self.switch-to-game($rest); Sentinel::QUIT }
            when '/games'  { self.show-games }
            when '/leave'  { self.handle-leave; Sentinel::QUIT }
            when '/lobby'  { $.app-ui.switch-to-lobby; Sentinel::QUIT }

            # Messaging
            when '/say'    { self.say-to-game($rest) }
            when '/msg'    { self.message-character($rest) }

            # Default: recommend help
            default { put 'Unknown slash command.  Use /help for a list of commands.' }
        }
    }

    method play-turn(::?CLASS:D:) {
        loop {
            self.process-pushed-messages;

            if $.client.gamestate == NotStarted {
                $.app-ui.put-colored("Waiting for $.game-type game to start.", 'bold');
            }

            my $styled-prompt = $.app-ui.styled-prompt(self.prompt-string);

            with $.input.prompt($styled-prompt) {
                my $input = .trim;
                if $input.starts-with('/') {
                    my $quit = self.handle-slash-command($input);
                    return if $quit === Sentinel::QUIT;
                }
                elsif $input.lc ~~ /^ [ '?' | 'help' | 'halp' ] / {
                    self.show-game-help;
                }
                elsif self.valid-turn($input) {
                    self.submit-turn($input);
                    return;
                }
                elsif $input {
                    put 'That\'s not a valid input!';
                }
            }
            else { put ''; self.handle-leave; return; }
        }
    }

    method valid-turn(Str:D $input) {
        $.client.valid-turn($input)
    }

    method submit-turn($input) {
        my $finished;
        await $.client.submit-turn($input, { self.show-turn-success($_) }).then: {
            if .status == Broken {
                self.show-error(.cause);
            }
            elsif .result.data<gamestate> >= Finished {
                $finished = True;
            }
        }
        self.game-finished if $finished;
    }

    method show-turn-success($response) {
        self.show-game-state($response);
    }

    method show-error($exception) {
        if $exception ~~ X::MUGS::Response::InvalidRequest {
            $.app-ui.put-colored($exception.error, 'yellow');
        }
        else {
            $.app-ui.put-colored($exception.message, 'red');
        }
    }

    method game-finished() {
        await $.client.leave;
    }
}


=begin pod

=head1 NAME

MUGS-UI-CLI - CLI UI for MUGS, including App and game UIs

=head1 SYNOPSIS

  # Set up a full-stack MUGS-UI-CLI development environment
  mkdir MUGS
  cd MUGS
  git clone git@github.com:Raku-MUGS/MUGS-Core.git
  git clone git@github.com:Raku-MUGS/MUGS-Games.git
  git clone git@github.com:Raku-MUGS/MUGS-UI-CLI.git

  cd MUGS-Core
  zef install --exclude="pq:ver<5>:from<native>" .
  mugs-admin create-universe

  cd ../MUGS-Games
  zef install .

  cd ../MUGS-UI-CLI
  zef install --deps-only .  # Or skip --deps-only if you prefer


  ### LOCAL PLAY

  # Play games using a local CLI UI, using an internal stub server and ephemeral data
  mugs-cli

  # Play games using an internal stub server accessing the long-lived data set
  mugs-cli --universe=<universe-name>  # 'default' if set up as above

  # Log in and play games on a WebSocket server using a local CLI UI
  mugs-cli --server=<host>:<port>


  ### GAME SERVERS

  # Start a TLS WebSocket game server on localhost:10000 using fake certs
  mugs-ws-server

  # Specify a different MUGS identity universe (defaults to "default")
  mugs-ws-server --universe=other-universe

  # Start a TLS WebSocket game server on different host:port
  mugs-ws-server --host=<hostname> --port=<portnumber>

  # Start a TLS WebSocket game server using custom certs
  mugs-ws-server --private-key-file=<path> --certificate-file=<path>

  # Write a Log::Timeline JSON log for the WebSocket server
  LOG_TIMELINE_JSON_LINES=log/mugs-ws-server mugs-ws-server


=head1 DESCRIPTION

B<NOTE: See the L<top-level MUGS repo|https://github.com/Raku-MUGS/MUGS> for more info.>

MUGS::UI::CLI is a CLI app (`mugs-cli`) and a set of UI plugins to play each
of the games in
L<MUGS-Core|https://github.com/Raku-MUGS/MUGS-Core> and
L<MUGS-Games|https://github.com/Raku-MUGS/MUGS-Games> via the CLI.

This Proof-of-Concept release only contains very simple turn-based guessing and
interactive fiction games, plus a simple lobby for creating identities and
choosing games to play.  Future releases will include many more games and
genres, plus better handling of asynchronous events such as inter-player
messaging.


=head1 ROADMAP

MUGS is still in its infancy, at the beginning of a long and hopefully very
enjoyable journey.  There is a
L<draft roadmap for the first few major releases|https://github.com/Raku-MUGS/MUGS/tree/main/docs/todo/release-roadmap.md>
but I don't plan to do it all myself -- I'm looking for contributions of all
sorts to help make it a reality.


=head1 CONTRIBUTING

Please do!  :-)

In all seriousness, check out L<the CONTRIBUTING doc|docs/CONTRIBUTING.md>
(identical in each repo) for details on how to contribute, as well as
L<the Coding Standards doc|https://github.com/Raku-MUGS/MUGS/tree/main/docs/design/coding-standards.md>
for guidelines/standards/rules that apply to code contributions in particular.

The MUGS project has a matching GitHub org,
L<Raku-MUGS|https://github.com/Raku-MUGS>, where you will find all related
repositories and issue trackers, as well as formal meta-discussion.

More informal discussion can be found on IRC in
L<Libera.Chat #mugs|ircs://irc.libera.chat:6697/mugs>.


=head1 AUTHOR

Geoffrey Broadwell <gjb@sonic.net> (japhb on GitHub and Libera.Chat)


=head1 COPYRIGHT AND LICENSE

Copyright 2021 Geoffrey Broadwell

MUGS is free software; you can redistribute it and/or modify it under the
Artistic License 2.0.

=end pod
