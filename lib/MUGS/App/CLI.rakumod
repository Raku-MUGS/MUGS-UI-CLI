# ABSTRACT: Core logic to set up and run a CLI game

use Terminal::ANSIColor;
use Terminal::LineEditor::RawTerminalInput;

use MUGS::Core;
use MUGS::Util::StructureValidator;
use MUGS::App::LocalUI;


# Use subcommand MAIN args
%PROCESS::SUB-MAIN-OPTS = :named-anywhere;


#| CLI App
class MUGS::App::CLI is MUGS::App::LocalUI {
    has Bool $.screen-reader;  #= Tune output for screen readers
    has Bool $.ansi;           #= Enable ANSI color
    has Terminal::LineEditor::CLIInput $!input .= new;
    has @!active-game-uis;

    method ui-type() { 'CLI' }

    method initialize() {
        callsame;
        $!screen-reader //= $.config.value('UI', 'Common', 'tune-for-screen-reader');
        $!ansi          //= $.config.value('UI', 'CLI',    'color');
    }

    method put-colored(Str $text, Str:D $color, Bool :$include-empty) {
        my $sanitized = self.sanitize-text($text);
        return unless $sanitized || $include-empty;
        put $!ansi ?? colored($sanitized, $color) !! $sanitized;
    }

    method put-sanitized(Str $text, Bool :$include-empty) {
        my $sanitized = self.sanitize-text($text);
        put $sanitized if $sanitized || $include-empty;
    }

    method sanitize-text(Str $text) {
        $text ?? $text.subst(/<:C+:Cc+:Cf+:Cn+:Co+:Cs-[\n]>+/, '', :g)
              !! ''
    }

    method present-tense-message(Str:D $text) {
        $text ~ ($.screen-reader ?? '.' !! ' ...')
    }

    method put-status-update(Str:D $text) {
        self.put-sanitized(self.present-tense-message($text));
    }

    method styled-prompt(Str:D $prompt) {
        $!ansi ?? colored($prompt, 'bold yellow') !! $prompt
    }

    method prompt-for-password(Str:D $prompt = 'Password') {
        $!input.prompt(self.styled-prompt("$prompt:"), :mask<*>);
    }

    method text-input(Str:D $label, Str :$default) {
        my $styled = self.styled-prompt($default ?? "$label [$default]:" !! "$label:");
        my $input;
        until $input {
            my $raw = $!input.prompt($styled);
            return unless $raw.defined;
            $input = $raw.trim || $default;
        }
        $input
    }

    method select-list(*@options) {
        # Silently handle trivial lists
        return unless @options;
        return @options[0].key if @options == 1;

        # Otherwise, provide a select list that can be selected by number
        for @options.kv -> $i, $p (:$key, :value($text)) {
            say "{$i+1}. $text";
        }

        my $option;
        until $option {
            my $new-option = $!input.prompt(self.styled-prompt("Selection:"));
            return unless $new-option.defined;
            $new-option .= trim;
            if $new-option ~~ /^ \d+ $/ && 1 <= $new-option <= @options {
                $option = +$new-option;
            }
            elsif $new-option {
                say "Invalid option; please choose a listed option number.";
            }
        }

        return @options[$option - 1].key;
    }

    method make-table(@columns, @data) {
        # XXXX: Correct for duowidth
        my @widths = @columns.map(*.chars // 1);
        for @data -> @row {
            die "Table data has wrong number of columns" if @row != @columns;

            for @row.kv -> $i, $v {
                @widths[$i] max= $v.chars;
            }
        }

        my $format = @widths.map('%-' ~ * ~ 's').join('  ');
        my @lines;
        @lines.push: colored(sprintf($format, |@columns), 'bold');
        @lines.push: sprintf($format, |$_) for @data;
        @lines
    }



    #| Connect to server and authenticate as a valid user
    method ensure-authenticated-session(Str $server, Str $universe) {
        my $decoded = self.decode-server($server);

        # Try to connect, bailing out if unable to do so
        (my $session = try self.connect($decoded<url> // $decoded<server>, $universe))
            or self.exit-with-errors("Unable to connect to MUGS server '$decoded<server>':", [$!]);

        my $username  = $decoded<username>
                     || $.config.value('Servers', $decoded<server>, 'user');
        my $password  = $.config.value('Servers', $decoded<server>, 'pass') // '';

        AUTHLOOP: while $password.defined {
            if $username {
                # Attempt authentication using current username and password
                try await $session.authenticate(:$username, :$password);
                last if $session.username;
                say "Authentication for user '$username' failed.";

                # Failed, get a new username (defaulting to the old one)
                $username = self.text-input('Username', :default($username));
            }

            USERLOOP: until $username {
                say "No username specified for this server; create a new one?";
                my $answer = self.select-list('yes' => 'Yes, create a new one.',
                                              'no'  => 'No, log in with an existing user.');
                last AUTHLOOP unless $answer.defined;

                if $answer eq 'yes' {
                    loop {
                        # Prompt for new username/password and create user
                        $username = self.text-input('Desired username')
                                    orelse next USERLOOP;
                        my ($pass1, $pass2);
                        repeat {
                            $pass1 = self.prompt-for-password('Desired password')
                                     orelse next USERLOOP;
                            $pass2 = self.prompt-for-password('Confirm password')
                                     orelse next USERLOOP;
                            say "Passwords don't match." unless $pass1 eq $pass2;
                        } until $pass1 eq $pass2;

                        try await $.session.create-account-owner(:$username, :password($pass1));
                        last AUTHLOOP if $session.username;
                        say "Unable to create user '$username'.";
                        $username = '';
                    }
                }
                else {
                    # No previous username, just request one from scratch
                    $username = self.text-input('Username') orelse last AUTHLOOP;
                }
            }

            # Factored out because it's actually a pain
            $password = self.prompt-for-password;
        }

        with $session.username {
            say "Logged in as $_." unless self.session-is-internal($session);
        }
        else {
            self.user-break;
        }
    }

    #| Use default identities or create and use new identities if needed
    method choose-identities() {
        callsame;
        my @need = ('a persona'   unless $.session.default-persona),
                   ('a character' unless $.session.default-character);
        return unless @need;

        my $username    = $.session.username;
        my $name-regex  = regex { ^ [\w+]+ % ' ' $ };
        my $invalid     = "Invalid name; only letters, numbers, underscores, and single spaces allowed.";

        print qq:to/NEED-IDENTITIES/;

            In order to play games, you will need to choose your identities.
            There are three kinds of MUGS identities, with different uses:

                User:       Logging in, security, and access control
                Persona:    Managing characters, interacting with players outside games
                Character:  Joining and playing games

            You are already logged in with your user ($username).
            You will need to create { @need.join(' and ') }.
            NEED-IDENTITIES

        with $.session.default-persona {
            put "You are using $_ as your persona."
        }
        else {
            until $.session.default-persona {
                my $prompt = "Please choose a screen name to create a persona";
                my $screen-name = self.text-input($prompt) orelse last;

                unless $screen-name ~~ $name-regex {
                    put $invalid if $screen-name;
                    next;
                }

                await $.session.create-persona(:$screen-name);
            }

            with $.session.default-persona {
                put "You have created $_ as your new persona.";
            }
            else {
                self.user-break;
            }
        }

        with $.session.default-character {
            put "You will join games as $_."
        }
        else {
            until $.session.default-character {
                my $prompt = "Please choose a screen name to create a character";
                my $screen-name = self.text-input($prompt) orelse last;

                unless $screen-name ~~ $name-regex {
                    put $invalid if $screen-name;
                    next;
                }

                await $.session.create-character(:persona-name($.session.default-persona),
                                                 :$screen-name);
            }

            with $.session.default-character {
                put "You have created $_ as your new character.";
            }
            else {
                self.user-break;
            }
        }

        put '';
    }

    #| Shutdown and exit with error status due to user breaking out of modal input
    method user-break() {
        put '';
        self.shutdown;
        exit 1;
    }

    #| Create and initialize a new game UI for a given game type and client
    method launch-game-ui(Str:D :$game-type, MUGS::Client::Game:D :$client, *%ui-opts) {
        @!active-game-uis[0].deactivate if @!active-game-uis;
        my $game-ui = callwith(:$game-type, :$client, :$.screen-reader, |%ui-opts);
        @!active-game-uis.unshift: $game-ui;
        $game-ui;
    }

    #| Switch an existing game UI to "top of stack"
    multi method switch-to-game-ui(UInt:D :$pos!) {
        return unless 0 < $pos < @!active-game-uis;

        @!active-game-uis[0].deactivate;
        @!active-game-uis.prepend: @!active-game-uis.splice($pos, 1);
        @!active-game-uis[0].activate;
    }

    #| Switch to an existing game UI by game ID
    multi method switch-to-game-ui(:$game-id!) {
        with @!active-game-uis.first(*.client.game-id eq $game-id, :k) -> $pos {
            self.switch-to-game-ui(:$pos);
        }
    }

    #| Switch to lobby UI, launching it if none already started
    method switch-to-lobby() {
        my $game-type = 'lobby';
        with @!active-game-uis.first(*.is-lobby, :k) -> $pos {
            self.switch-to-game-ui(:$pos);
        }
        else {
            self.launch-game-ui(:$game-type, :client($.lobby-client));
        }
    }

    #| Send the current UI to the end of the UI list
    method send-current-ui-to-back() {
        return unless @!active-game-uis > 1;

        @!active-game-uis[0].deactivate;
        @!active-game-uis.push: @!active-game-uis.shift;
        @!active-game-uis[0].activate;
    }

    #| Leave the current game UI, switching to the next frontmost if any
    method leave-current-ui() {
        return unless @!active-game-uis;

        # Handle exiting from entire app by pressing ^D
        if $*IN.eof {
            self.leave-all-games;
        }
        # Only leave the lobby if it is the last UI; otherwise just move
        # the lobby to the back.
        elsif @!active-game-uis[0].is-lobby && @!active-game-uis > 1 {
            self.send-current-ui-to-back;
        }
        # Normal case: just leave the current game and UI
        else {
            my $client = @!active-game-uis[0].client;
            await $client.leave if $.session.client-is-active($client);
            @!active-game-uis[0].shutdown;
            @!active-game-uis.shift;
            @!active-game-uis[0].activate if @!active-game-uis;
        }
    }

    #| Leave all active games and game UIs
    method leave-all-games() {
        await @!active-game-uis.map(*.client.leave);
        .shutdown for @!active-game-uis;
        @!active-game-uis = ();
    }

    #| Play turns of the frontmost UI (switching when order changes)
    method play-current-game() {
        while @!active-game-uis {
            my $current = @!active-game-uis[0];
            $current.play-turn;
            self.leave-current-ui unless $.session.client-is-active($current.client);
        }
    }

    #| Shut down the overall MUGS client app (as cleanly as possible)
    method shutdown() {
        self.leave-all-games;
        callsame;
    }
}


#| Common options that work for all subcommands
my $common-args = :(Str :$server, Str :$universe,
                    Bool :$debug, Bool :$screen-reader, Bool :$ansi);

#| Add description of common arguments/options to standard USAGE
sub GENERATE-USAGE(&main, |capture) is export {
    &*GENERATE-USAGE(&main, |capture).subst(' <options>', '', :g)
    ~ q:to/OPTIONS/.trim-trailing;


        Common options for all commands:
          --screen-reader   Tune output for screen reader use
          --ansi            Enable ANSI colors (default)
          --server=<Str>    Specify an external server (defaults to internal)
          --universe=<Str>  Specify a local universe (internal server only)
          --debug           Enable debug output
        OPTIONS
}


#| Run a perf test of echo "game"
multi MAIN('perf', UInt:D $count = 100_000,
           |options where $common-args) is export {
    my $*DEBUG = options<debug> // ?%*ENV<MUGS_DEBUG>;

    my $ui = MUGS::App::CLI.new;
    $ui.initialize;
    $ui.ensure-authenticated-session(options<server>   // Str,
                                     options<universe> // Str);
    $ui.choose-identities;

    my $game-type = 'echo';
    my $client = $ui.new-game-client(:$game-type);
    my $runner = $ui.launch-game-ui(:$game-type, :$client);
    $runner.perf-test($count);

    $ui.shutdown;
}

#| Play a requested CLI game
multi MAIN($game-type, |options where $common-args) is export {
    play-via-local-ui(MUGS::App::CLI, :$game-type, |options)
}

#| Enter the game choice lobby (DEFAULT)
multi MAIN('lobby',
           |options where $common-args) is export {
    play-via-local-ui(MUGS::App::CLI, :game-type<lobby>, |options)
}

#| Default to showing the lobby / game choice UI
multi MAIN(|options where $common-args) is export is hidden-from-USAGE {
    play-via-local-ui(MUGS::App::CLI, :game-type<lobby>, |options)
}
