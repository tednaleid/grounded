#!/usr/bin/env -S uv run --script
# ABOUTME: ChargePoint home charger status PoC - reports idle/charging/error.
# ABOUTME: Reads CP_USERNAME and CP_COULOMB_TOKEN from .env, prints state + exit code.
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "python-chargepoint>=2.3.2",
#     "python-dotenv>=1.0",
# ]
# ///
import asyncio
import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from python_chargepoint import ChargePoint
from python_chargepoint.exceptions import (
    CommunicationError,
    DatadomeCaptcha,
    InvalidSession,
)

load_dotenv(Path(__file__).parent / ".env")


async def main() -> int:
    username = os.environ.get("CP_USERNAME", "").strip()
    token = os.environ.get("CP_COULOMB_TOKEN", "").strip()
    if not username or not token:
        print("ERROR: CP_USERNAME and CP_COULOMB_TOKEN must be set in .env")
        return 3

    try:
        client = await ChargePoint.create(username=username, coulomb_token=token)
    except DatadomeCaptcha as e:
        print(f"ERROR: blocked by Datadome captcha during login. {e}")
        return 3

    try:
        charger_ids = await client.get_home_chargers()
        if not charger_ids:
            print("ERROR: no home chargers registered to this account")
            return 3
        charger_id = charger_ids[0]

        charger = await client.get_home_charger_status(charger_id)
        print(f"--- charger {charger_id} ---")
        print(f"brand:           {charger.brand!r}")
        print(f"model:           {charger.model!r}")
        print(f"charging_status: {charger.charging_status!r}")
        print(f"is_plugged_in:   {charger.is_plugged_in}")
        print(f"is_connected:    {charger.is_connected}")
        print(f"amperage_limit:  {charger.amperage_limit}")

        if not charger.is_connected:
            print("STATE: OFFLINE")
            return 2

        try:
            user_status = await client.get_user_charging_status()
        except (CommunicationError, InvalidSession) as e:
            print(f"STATE: ERROR ({type(e).__name__}: {e})")
            return 3

        if user_status is None:
            state = "PLUGGED_WAITING" if charger.is_plugged_in else "IDLE"
            print(f"STATE: {state}")
            return 0

        print(f"--- user_status ---")
        print(f"session_id:      {user_status.session_id}")
        print(f"state:           {user_status.state!r}")
        print(f"start_time:      {user_status.start_time}")

        try:
            session = await client.get_charging_session(user_status.session_id)
        except CommunicationError as e:
            print(f"STATE: ERROR (session fetch: {e})")
            return 3

        print(f"--- session {session.session_id} ---")
        print(f"charging_state:  {session.charging_state!r}")
        print(f"power_kw:        {session.power_kw}")
        print(f"energy_kwh:      {session.energy_kwh}")
        print(f"miles_added:     {session.miles_added}")
        print(f"last_update:     {session.last_update_data_timestamp}")

        if session.power_kw > 0:
            print("STATE: CHARGING")
            return 0
        if session.charging_state == "fully_charged":
            print("STATE: IDLE (fully_charged)")
            return 0
        print(f"STATE: UNKNOWN (charging_state={session.charging_state!r})")
        return 4
    except DatadomeCaptcha as e:
        print(f"ERROR: blocked by Datadome captcha. {e}")
        return 3
    finally:
        await client.close()


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
