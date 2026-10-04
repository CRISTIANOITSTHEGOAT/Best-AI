#!/usr/bin/env node
/*
	ORBIT GRAB — test runner
	========================
	Runs tests/smoke_test.lua in fengari (a Lua VM implemented in JS),
	with tests/roblox_mock.lua standing in for the engine.

		npm install fengari
		node tests/run.js

	Exits non-zero if any check fails.
*/

const fs = require("fs");
const path = require("path");
const { lua, lauxlib, lualib, to_luastring } = require("fengari");

const ROOT = path.resolve(__dirname, "..");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// readfile(path) -> string | nil
lua.lua_pushcfunction(L, (L) => {
	const rel = lua.lua_tojsstring(L, 1);
	const abs = path.resolve(ROOT, rel);
	try {
		lua.lua_pushstring(L, to_luastring(fs.readFileSync(abs, "utf8")));
	} catch (e) {
		lua.lua_pushnil(L);
	}
	return 1;
});
lua.lua_setglobal(L, to_luastring("readfile"));

const PRELUDE = `
-- loadlua(file[, globalName]) — loads a .lua file and optionally stashes
-- its return value in a global. Used to fake Roblox's require().
function loadlua(file, globalName)
	local src = readfile(file)
	if not src then error("no such file: " .. tostring(file), 2) end
	local chunk, err = load("return (function()\\n" .. src .. "\\nend)()", "@" .. file)
	if not chunk then error("compile error in " .. file .. ": " .. tostring(err), 2) end
	local result = chunk()
	if globalName then _G[globalName] = result end
	return result
end

function loadluafile(file) return loadlua(file) end
`;

function run(code, name, nresults = 0) {
	const status = lauxlib.luaL_loadbuffer(L, to_luastring(code), to_luastring(name));
	if (status !== lua.LUA_OK) {
		console.error("COMPILE ERROR: " + lua.lua_tojsstring(L, -1));
		process.exit(2);
	}
	// install debug.traceback as the message handler so we get a stack trace:
	// push it, then insert it *below* the chunk (lua_pcall expects the callee
	// at top-(nargs+1)).
	const chunkIndex = lua.lua_gettop(L);
	lua.lua_getglobal(L, to_luastring("debug"));
	lua.lua_getfield(L, -1, to_luastring("traceback"));
	lua.lua_remove(L, -2);
	lua.lua_insert(L, chunkIndex);
	const r = lua.lua_pcall(L, 0, nresults, chunkIndex);
	if (r !== lua.LUA_OK) {
		console.error("\nLUA ERROR: " + lua.lua_tojsstring(L, -1) + "\n");
		process.exit(3);
	}
	return r;
}

run(PRELUDE, "=prelude");

const testFile = process.argv[2] || "tests/smoke_test.lua";
run(fs.readFileSync(path.resolve(ROOT, testFile), "utf8"), testFile, 1);

const failures = lua.lua_tointeger(L, -1);
process.exit(failures && failures > 0 ? 1 : 0);
