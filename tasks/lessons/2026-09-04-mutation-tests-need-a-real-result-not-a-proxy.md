# A mutation test that reads a proxy reports every mutation as caught

Six deliberate breakages were run against `fleet_pins.py` and all six came back identical — because the harness took `tail -1` of a suite that prints **no summary line**, so it read the last assertion's text, which never changes. It looked like total coverage and measured nothing. Counting `PASS`/`FAIL` lines instead showed 5 caught and **1 missed**: a guard no assertion covered.

Mutation testing is only worth running if the harness reads the actual result. Count failures, or make the suite print a summary and parse that — never trust the last line of output to represent the run. And a mutation that changes nothing is the finding, not a formality: it means a branch of the code is unasserted, which is exactly what the exercise is for.

Related: [[2026-09-04-a-test-can-match-its-own-fixture-name]].
