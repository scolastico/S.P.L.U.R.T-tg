"""Exercise imported legacy saves in a disposable, paused Babylon test child.

The input checkpoint is read-only. No live server or player save is modified.
Requires a built workshop fixture containing an alarm, cycling pump, connected
canisters, an R&D console, and an autolathe (such as the original PoC save).
"""
import argparse
import json
from pathlib import Path
import secrets
import shutil
import socket
import subprocess
import time
import uuid
from urllib.parse import urlencode

from protocol import topic
from supervisor import Driver


class Fixture:
    def __init__(self, args):
        self.args = args
        self.template = Path(__file__).resolve().parents[2]
        self.data = Path(args.data_directory).resolve()
        if self.data.exists():
            raise RuntimeError("Use a new test data directory")
        if args.port in (1339, 1361):
            raise RuntimeError("Refusing a player/lobby port")
        with socket.socket() as probe:
            probe.bind(("127.0.0.1", args.port))
        self.secret = secrets.token_urlsafe(32)
        world = dict(id=uuid.uuid4().hex, owner="reloadfixture")
        run = dict(id=uuid.uuid4().hex, secret=self.secret)
        config = dict(template_directory=str(self.template), data_directory=str(self.data),
                      config_directory=str(Path(args.config_directory).resolve()))
        self.root = Driver(config).prepare(world, run)
        for ext in ("dmb", "rsc"):
            shutil.copy2(self.template / f"babylon-test.{ext}", self.root / f"babylon.{ext}")
        self.process = None
        self.stage = 0

    def request(self, action, **payload):
        result = topic(self.args.port, self.secret, action, payload, timeout=180)
        assert not result.get("error"), result
        return result

    def inspect(self, target, *fields):
        return self.request("inspect", target=target, vars=list(fields))["vars"]

    def call(self, target, proc, *args):
        return self.request("call", target=target, proc=proc, args=list(args))["result"]

    def set(self, target, name, value):
        self.request("set_var", target=target, var=name, value=value)

    def find(self, path):
        return [item for item in self.request("find", type=path, limit=100)["matches"] if item["z"] == 2]

    def one(self, path):
        items = self.find(path)
        assert items, f"Fixture needs {path}"
        return items[0]["ref"]

    def start(self, checkpoint, legacy=False):
        self.stage += 1
        checkpoint = Path(checkpoint)
        state = json.loads((checkpoint / "state.json").read_text(encoding="utf-8-sig"))
        if legacy:
            for record in state["records"]:
                for field in ("alarm_thresholds", "alarm_mode", "cycle_settings", "cycle_internal",
                              "cycle_external", "cycle_remaining", "portable_port"):
                    record.pop(field, None)
                if isinstance(record["references"], dict):
                    record["references"].pop("circuit", None)
        shutil.copy2(checkpoint / "map.dmm", self.root / "_maps/babylon/active.dmm")
        (self.root / "data/babylon/resume-state.json").write_text(json.dumps(state))
        params = urlencode({"config-directory": str(self.root / "babylon-config"),
                            "babylon-owner": "reloadfixture", "babylon-hold": "1"})
        with open(self.data / f"stage-{self.stage}.log", "wb") as log:
            self.process = subprocess.Popen([self.args.dreamdaemon, "babylon.dmb", str(self.args.port),
                                            "-ip", "127.0.0.1", "-trusted", "-close", "-params", params],
                                           cwd=self.root, stdout=log, stderr=log,
                                           creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        (self.data / "process.json").write_text(json.dumps(dict(pid=self.process.pid, port=self.args.port)))
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise RuntimeError("Fixture exited during startup")
            try:
                status = self.request("status")
                assert not status.get("error"), status
                if status["ready"]:
                    assert status["paused"], status
                    return
            except (OSError, ValueError):
                pass
            time.sleep(2)
        raise TimeoutError("Fixture did not become ready")

    def terminate(self):
        if self.process and self.process.poll() is None:
            # Only this harness's disposable child; never a PID from a player.
            self.process.terminate()
            self.process.wait(timeout=30)

    def save(self):
        result = self.request("save")
        assert result.get("ok"), result
        path = self.root / "data/babylon/saves" / result["generation"]
        return path, json.loads((path / "state.json").read_text())

    def tool(self, target, proc, path):
        self.call("builder", "drop_all_held_items")
        tool = self.request("spawn", type=path, target="builder")["object"]["ref"]
        self.call("builder", "put_in_hands", {"ref": tool})
        builder = self.request("inspect", target="builder", vars=[])["object"]["ref"]
        return self.call(target, proc, {"ref": builder}, {"ref": tool})

    def connected(self):
        result = []
        for item in self.find("/obj/machinery/portable_atmospherics/canister"):
            values = self.inspect(item["ref"], "connected_port", "air_contents", "anchored")
            if not values["connected_port"]:
                continue
            assert values["anchored"]
            port = values["connected_port"]["ref"]
            assert self.inspect(port, "connected_device")["connected_device"]["ref"] == item["ref"]
            airs = self.call(port, "return_airs_for_reconcilation")
            assert any(entry["entry"]["ref"] == values["air_contents"]["ref"] for entry in airs["entries"])
            result.append(item)
        return result

    def doors(self):
        for door in self.find("/obj/machinery/door/airlock"):
            values = self.inspect(door["ref"], "density", "airlock_state", "operating", "animation")
            assert not values["operating"] and not values["animation"], (door, values)
            assert values["airlock_state"] == ("closed" if values["density"] else "open"), (door, values)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dreamdaemon", required=True)
    parser.add_argument("--config-directory", required=True)
    parser.add_argument("--checkpoint", required=True)
    parser.add_argument("--data-directory", required=True)
    parser.add_argument("--port", type=int, default=1459)
    args = parser.parse_args()
    fixture = Fixture(args)
    f = fixture
    try:
        f.start(args.checkpoint, legacy=True)
        for kind in ("mouse", "snail", "stoat"):
            assert not f.find(f"/mob/living/basic/{kind}"), kind
        f.doors()
        attached = f.connected()
        assert len(attached) >= 2, "Fixture needs two connected canisters"
        loose = attached[-1]
        loose_position = (loose["x"], loose["y"])
        f.call(loose["ref"], "disconnect")
        pump = f.one("/obj/machinery/atmospherics/components/unary/airlock_pump")
        assert f.inspect(pump, "can_unwrench")["can_unwrench"]
        sides = f.inspect(pump, "internal_airlocks", "external_airlocks")
        inner = sides["internal_airlocks"]["entries"][0]["entry"]["ref"]
        outer = sides["external_airlocks"]["entries"][0]["entry"]["ref"]
        for door, density in ((outer, 0), (inner, 1)):
            f.set(door, "density", density)
            f.call(door, "set_airlock_state")
        f.set(inner, "operating", 1)
        f.set(pump, "internal_pressure_target", 222)
        f.set(pump, "external_pressure_target", 7)
        alarm = f.one("/obj/machinery/airalarm")
        f.call(alarm, "set_tlv_no_checks")
        thresholds = f.inspect(alarm, "tlv_collection")["tlv_collection"]
        pressure = next(e["value"]["ref"] for e in thresholds["entries"] if e["entry"] == "pressure")
        f.set(pressure, "hazard_min", 0)
        f.set(pressure, "warning_max", 234)
        f.call(alarm, "select_mode", {"ref": alarm}, {"typepath": "/datum/air_alarm_mode/contaminated"}, 0)
        console = f.one("/obj/machinery/computer/rdconsole")
        location = f.request("inspect", target=console, vars=[])["object"]
        console_position = (location["x"], location["y"])
        f.call("builder", "forceMove", {"turf": [*console_position, 2]})
        assert f.inspect(console, "circuit")["circuit"], "Legacy machine circuit not recovered"
        f.set(console, "time_to_unscrew", 0)
        f.tool(console, "screwdriver_act", "/obj/item/screwdriver")
        frame = next(item["ref"] for item in f.find("/obj/structure/frame/computer") if (item["x"], item["y"]) == console_position)
        board = f.inspect(frame, "circuit")["circuit"]["ref"]
        for proc, tool, expected in (("crowbar_act", "/obj/item/crowbar", 3),
                                     ("wirecutter_act", "/obj/item/wirecutters", 2),
                                     ("screwdriver_act", "/obj/item/screwdriver", 1),
                                     ("crowbar_act", "/obj/item/crowbar", 0)):
            f.tool(frame, proc, tool)
            assert f.inspect(frame, "state")["state"] == expected
        assert not f.inspect(frame, "circuit")["circuit"]
        f.call("builder", "drop_all_held_items")
        f.call("builder", "put_in_hands", {"ref": board})
        builder = f.request("inspect", target="builder", vars=[])["object"]["ref"]
        assert f.call(frame, "install_board", {"ref": builder}, {"ref": board}, 1)
        f.tool(frame, "screwdriver_act", "/obj/item/screwdriver")
        for path, amount, proc in (("/obj/item/stack/cable_coil", 5, "add_cabling"),
                                   ("/obj/item/stack/sheet/glass", 2, "add_glass")):
            f.call("builder", "drop_all_held_items")
            # Keep newly created stacks off the floor so they cannot merge
            # into the cables/glass just removed from this same frame.
            item = f.request("spawn", type=path, location={"ref": builder})["object"]["ref"]
            f.set(item, "amount", amount)
            f.call("builder", "put_in_hands", {"ref": item})
            assert f.call(frame, proc, {"ref": builder}, {"ref": item}, 0)
        lathe = f.one("/obj/machinery/autolathe")
        materials = f.inspect(lathe, "materials")["materials"]["ref"]
        stock = f.call(materials, "total_amount")
        f.call(materials, "babylon_test_invalid_material")
        ui = f.call(lathe, "ui_data")
        assert next(e["value"] for e in ui["entries"] if e["entry"] == "materials")["length"]
        assert f.call(materials, "total_amount") == stock
        friend = f.call("session", "ensure_player", "regressionfriend")["ref"]
        friend_body = f.inspect(friend, "builder")["builder"]["ref"]
        bag = f.request("spawn", type="/obj/item/storage/backpack", target=friend_body)["object"]["ref"]
        f.call(friend_body, "put_in_hand", {"ref": bag}, 2, 1)
        checkpoint, before = f.save()
        assert {"reloadfixture", "regressionfriend"} <= set(before["players"])
        f.terminate()
        f.start(checkpoint)
        f.doors()
        assert len(f.connected()) == len(attached) - 1
        loose = next(item for item in f.find("/obj/machinery/portable_atmospherics/canister") if (item["x"], item["y"]) == loose_position)
        assert not f.inspect(loose["ref"], "connected_port", "anchored")["connected_port"]
        pump = f.one("/obj/machinery/atmospherics/components/unary/airlock_pump")
        settings = f.inspect(pump, "can_unwrench", "internal_pressure_target", "external_pressure_target", "internal_airlocks", "external_airlocks")
        assert settings["can_unwrench"] and settings["internal_pressure_target"] == 222 and settings["external_pressure_target"] == 7
        assert f.inspect(settings["external_airlocks"]["entries"][0]["entry"]["ref"], "density")["density"] == 0
        assert f.inspect(settings["internal_airlocks"]["entries"][0]["entry"]["ref"], "density")["density"] == 1
        checkpoint2, after = f.save()
        by_id = {record["id"]: record for record in before["records"]}
        for record in after["records"]:
            old = by_id.get(record["id"], {})
            for field in ("alarm_thresholds", "alarm_mode", "cycle_settings", "cycle_internal", "cycle_external", "portable_port", "materials"):
                if field in old:
                    assert record[field] == old[field], (record["id"], field)
        assert set(before["players"]) == set(after["players"])
        assert before["players"]["regressionfriend"]["builder"] == after["players"]["regressionfriend"]["builder"]
        frame = next(item["ref"] for item in f.find("/obj/structure/frame/computer") if (item["x"], item["y"]) == console_position)
        assert f.inspect(frame, "state", "circuit")["state"] == 4
        assert f.inspect(frame, "circuit")["circuit"]
        f.tool(frame, "screwdriver_act", "/obj/item/screwdriver")
        assert any((item["x"], item["y"]) == console_position for item in f.find("/obj/machinery/computer/rdconsole"))
        report = dict(passed=True, legacy_import=True, no_random_critters=True,
                      door_collision_and_animation=True, alarm_thresholds_and_mode=True,
                      cycling_pump_settings_and_removability=True, canister_attachments=True,
                      deliberate_disconnection=True, circuit_extraction_and_reassembly=True,
                      autolathe_ui_and_stock=True, multiplayer_roster=True,
                      generations=[checkpoint.name, checkpoint2.name])
        (f.data / "result.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, indent=2))
    finally:
        f.terminate()


if __name__ == "__main__":
    main()
