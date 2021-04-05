# ABSTRACT: Simple CLI UI for game selection lobby

use MUGS::Core;
use MUGS::Client::Game::Lobby;
use MUGS::UI::CLI;

enum State < SelectType >;

my %prompts =
    SelectType => 'Select a game type';


#| CLI UI for game selection lobby
class MUGS::UI::CLI::Game::Lobby is MUGS::UI::CLI::Game {
    has State $.state = State(0);

    method game-type()     { 'lobby' }
    method prompt-string() { %prompts{$.state} ~ ' > ' }
    method is-lobby()      { True }

    method show-available-game-types(::?CLASS:D: Bool :$all) {
        my @available = self.available-game-types(:$all).grep(*<game-type> ne 'lobby');
        my @columns   = < TYPE GENRES DESCRIPTION >;
        my @data      = @available.sort({.<genre-tags>, .<game-type>}).map: {
            (.<game-type>, .<genre-tags>.join(','), .<game-desc>)
        }

        if @data {
            put 'Known game types:';
            .indent(4).put for $.app-ui.make-table(@columns, @data);
        }
        else {
            put q:to/NONE/;
                There are no game-type matches between server, client, and UI.
                You may need to install game plugins or use a different UI.
                NONE
        }
    }

    method show-active-games(::?CLASS:D: Bool :$all) {
        my @active = self.active-games(:$all).grep(*<game-type> ne 'lobby').sort:
                         { $^a<game-type> cmp $^b<game-type> ||
                           $^a<game-id>   <=> $^b<game-id>   };
        my @columns = < JOINED ID TYPE STATUS WAITING >;
        my @data = @active.map: {
            my $players = .<num-participants>;
            my $joined  = $.client.session.games{.<game-id>} ?? '*' !!
                          .<my-characters>                   ?? '!' !! '';
            my $needed  = max(.<config><min-players>, .<config><start-players>);
            my $full    = $players >= .<config><max-players>;
            my $filling = .<gamestate> eq 'NotStarted' && $players < $needed;
            my $waiting = $filling ?? "$players/$needed" !!
                          $full    ?? '-full-'           !! '';

            ($joined, .<game-id>, .<game-type>, .<gamestate>, $waiting)
        }

        if @data {
            put 'Active games:';
            .indent(4).put for $.app-ui.make-table(@columns, @data);
        }
        else {
            put 'There are no already active games that are playable in this UI.';
        }
    }

    method show-initial-state(::?CLASS:D:) {
        self.show-available-game-types;
        put '';
        self.show-active-games;
        put '';
    }

    method show-game-help(::?CLASS:D:) {
        put 'You are in the game lobby, and can choose a game to play.';
        put '';
        put self.general-help;

        self.show-available-game-types;
        put '';
        self.show-active-games;
        put '';
    }

    method valid-turn($choice) {
        $choice.lc ∈ self.available-game-types.map(*<game-type>)
    }

    method submit-turn($choice) {
        my $game-type = $choice.lc;
        $.app-ui.put-sanitized($.app-ui.present-tense-message("Launching $game-type"));
        my $client = $.app-ui.new-game-client(:$game-type);
        $.app-ui.launch-game-ui(:$game-type, :$client);
    }
}


# Register this class as a valid game UI
MUGS::UI::CLI::Game::Lobby.register;
