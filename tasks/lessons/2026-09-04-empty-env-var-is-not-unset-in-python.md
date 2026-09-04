# An empty env var is "unset" in bash and a value in Python

`${VAR:-default}` falls back when the variable is empty; `os.environ.get("VAR", "default")` returns `""`. So the same environment produces different behaviour in the two halves of this repo, and the Python half fails destructively: `Path(root) / ""` is the root **directory**, which `.exists()` accepts and `read_text()` cannot read — `IsADirectoryError`, exit 1, which `taxonomy-check.yml` renders as a false "version collision detected".

When a config value is read by both bash and Python, decide once what empty means and make both agree — `(os.environ.get(x) or "").strip() or default`. Give any CI input feeding such a var a real default, never `''`. This is the same shape as v1.30's registry booleans, where `jq 'select(.x == true)'` excluded a string `"false"` while Python's `.get(x, False)` included it: one config, two readers, opposite answers.

Related: [[2026-09-04-a-feature-nobody-can-reach]].
