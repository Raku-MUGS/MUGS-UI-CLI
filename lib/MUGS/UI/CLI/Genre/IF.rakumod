# ABSTRACT: General CLI for Interactive Fiction games

use MUGS::Core;
use MUGS::Client::Genre::IF;
use MUGS::UI::CLI;


#| CLI for Interactive Fiction games
class MUGS::UI::CLI::Genre::IF is MUGS::UI::CLI::Game {
    method show-initial-state(::?CLASS:D:) {
        self.show-game-state($.client.initial-state);
    }

    method show-game-state($response) {
        my %data := $response ~~ Map ?? $response !! $response.data;

        if %data<gamestate> >= Finished {
            given $.client.my-winloss($response) {
                when Loss { $.app-ui.put-colored('You have lost.', 'bold') }
                when Win  { $.app-ui.put-colored('You have won!',  'bold') }
            }
            return;
        }

        my sub title($title) {
            $.app-ui.put-colored($title, 'bold');
            put '';
        }

        with %data<pre-message> {
            title(%data<pre-title>);
            $.app-ui.put-sanitized($_);
            put '--';
            put '';
        }

        with %data<message> {
            $.app-ui.put-sanitized($_);
        }
        orwith %data<inventory> {
            $.app-ui.put-sanitized($_ ?? 'Inventory: ' ~ .join(', ')
                                      !! 'Nothing in your inventory.');
        }
        orwith %data<location> {
            title(.<name>);
            $.app-ui.put-sanitized($_) with .<description>;
            if .<things> -> @items {
                $.app-ui.put-sanitized("\nThings: {@items.join(', ')}");
            }
            if .<exits> -> @exits {
                $.app-ui.put-sanitized("\nExits: {@exits.join(', ')}");
            }
            if .<characters> -> @chars {
                my @not-me = @chars.grep(* ne $.client.character-name);
                $.app-ui.put-sanitized("\nAlso here: {@not-me.join(', ')}") if @not-me;
            }
        }
    }
}
