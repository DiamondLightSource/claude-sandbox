/**
 * claude-sandbox tag for Pi's footer.
 *
 * Installed to ~/.pi/agent/extensions/ by `claude-sandbox doctor --fix`.
 * Shows host:tag, the short hostname and the claude-sandbox container tag,
 * so a Pi session shows which host and container it runs in, as the Claude
 * status line and the shell prompts do. Outside a launcher-made container
 * there is no tag file and the footer shows the hostname alone.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { hostname } from "node:os";

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (!ctx.hasUI) return;
		let tag = "";
		try {
			tag = readFileSync("/etc/claude-sandbox-tag", "utf8").trim();
		} catch {
			// Not a launcher-made container: show the hostname alone.
		}
		const host = hostname().split(".")[0];
		ctx.ui.setStatus("claude-sandbox-tag", ctx.ui.theme.fg("accent", tag ? `${host}:${tag}` : host));
	});
}
