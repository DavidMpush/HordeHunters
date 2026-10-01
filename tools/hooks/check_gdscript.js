// Claude Code PostToolUse hook: parse-checks an edited GDScript file with Godot.
// Reports parse errors back to Claude (exit 2) so they are fixed immediately.
const { spawnSync } = require("child_process");
const path = require("path");

const GODOT = "C:\\Users\\vrxby\\Documents\\Codex\\Godot\\Godot_v4.7.2-stable_win64_console.exe";
const PROJECT = path.resolve(__dirname, "..", "..");

let input = "";
process.stdin.on("data", (chunk) => (input += chunk));
process.stdin.on("end", () => {
	let file;
	try {
		file = JSON.parse(input).tool_input?.file_path;
	} catch {
		process.exit(0);
	}
	if (!file || !file.endsWith(".gd")) process.exit(0);
	const relative = path.relative(PROJECT, path.resolve(file));
	if (relative.startsWith("..")) process.exit(0);
	const resPath = "res://" + relative.split(path.sep).join("/");
	const run = spawnSync(GODOT, ["--headless", "--path", PROJECT, "--check-only", "--script", resPath], {
		encoding: "utf8",
		timeout: 20000,
	});
	const output = `${run.stdout || ""}
${run.stderr || ""}`;
	const problems = output
		.split(/\r?\n/)
		.filter((line) => /SCRIPT ERROR|Parse Error|ERROR:|at: /.test(line))
		.slice(0, 12);
	if (problems.length > 0) {
		process.stderr.write(`Godot parse check failed for ${resPath}:\n${problems.join("\n")}\n`);
		process.exit(2);
	}
	process.exit(0);
});
