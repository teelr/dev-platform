"""{{PROJECT_NAME}} entry point.

Loads config, instantiates the kermit-harness runtime, runs a one-shot agent
call. Replace the placeholder logic with your agent's actual flow.
"""
from __future__ import annotations

import logging
import os
import sys

from dotenv import load_dotenv

from backend.agent import run_once


def main() -> int:
    load_dotenv()

    logging.basicConfig(
        level=os.environ.get("LOG_LEVEL", "INFO").upper(),
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
    )
    log = logging.getLogger("{{PROJECT_NAME}}")

    if not os.environ.get("KERMIT_API_KEY"):
        log.error("KERMIT_API_KEY missing from environment (.env)")
        return 1

    log.info("starting {{PROJECT_NAME}}")
    try:
        result = run_once()
        log.info("done", extra={"result": result})
        return 0
    except Exception:
        log.exception("agent failed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
