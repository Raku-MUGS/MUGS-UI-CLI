# ABSTRACT: Simple CLI for echo test

use MUGS::Core;
use MUGS::Client::Game::Echo;
use MUGS::UI::CLI::Genre::Test;


#| UI for echo test
class MUGS::UI::CLI::Game::Echo is MUGS::UI::CLI::Genre::Test {
    method game-type()     { 'echo' }
    method prompt-string() { 'Enter a message >' }

    method show-initial-state(::?CLASS:D:) { }
    method show-echo($response) { $.app-ui.put-sanitized($response.data<echo>) }
    method valid-turn($message) { ?$message }
    method submit-turn($message) {
        await $.client.send-echo-message: $message, { self.show-echo($_) };
    }

    method game-help() {
        'Enter a message to send to the server, and it will echo back.';
    }

    method perf-test(::?CLASS:D: UInt:D $count = 100_000) {
        put $.app-ui.present-tense-message("Timing $count echo responses");

        my $t0 = now;
        await $.client.send-echo-message(~$_) for ^$count;
        my $t1 = now;

        my $ave   = ($t1 - $t0) / $count;
        my $scale = $ave > .001 ?? 1000 !! 1_000_000;
        my $unit  = $scale == 1000 ?? 'ms' !! 'μs';
        printf "$count echos in %.3fs = %.1f%s average\n",
            $t1 - $t0, $scale * $ave, $unit;
    }
}


# Register this class as a valid game UI
MUGS::UI::CLI::Game::Echo.register;
