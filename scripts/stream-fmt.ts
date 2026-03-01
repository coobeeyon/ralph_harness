#!/usr/bin/env bun
/**
 * Formats Claude Code stream-json output for human reading.
 * Usage: claude --output-format stream-json | bun scripts/stream-fmt.ts
 */
export {}

const isTTY = Boolean(process.stdout.isTTY)
const DIM = isTTY ? "\x1b[2m" : ""
const BOLD = isTTY ? "\x1b[1m" : ""
const CYAN = isTTY ? "\x1b[36m" : ""
const YELLOW = isTTY ? "\x1b[33m" : ""
const GREEN = isTTY ? "\x1b[32m" : ""
const RED = isTTY ? "\x1b[31m" : ""
const RESET = isTTY ? "\x1b[0m" : ""

const indent = (s: string): string =>
	s.split("\n").map(l => `\t${l}`).join("\n")

/** Collapse large fenced code blocks (file dumps) to a single line */
const collapseCodeBlocks = (s: string): string => {
	const lines = s.split("\n")
	const out: string[] = []
	let inBlock = false
	let blockStart = 0
	for (let i = 0; i < lines.length; i++) {
		if (!inBlock && lines[i].startsWith("```")) {
			inBlock = true
			blockStart = i
			continue
		}
		if (inBlock && lines[i].trimEnd() === "```") {
			const blockLen = i - blockStart - 1
			if (blockLen > 10) {
				out.push(`(${blockLen} lines omitted)`)
			} else {
				for (let j = blockStart; j <= i; j++) out.push(lines[j])
			}
			inBlock = false
			continue
		}
		if (!inBlock) out.push(lines[i])
	}
	if (inBlock) {
		for (let j = blockStart; j < lines.length; j++) out.push(lines[j])
	}
	return out.join("\n")
}

const TODO_TOOLS = new Set(["TodoRead", "TodoWrite", "TaskCreate", "TaskGet", "TaskUpdate", "TaskList"])
const QUIET_TOOLS = new Set(["Read"])
const suppressedIds = new Set<string>()

const formatEvent = (line: string): string | null => {
	let event: Record<string, unknown>
	try {
		event = JSON.parse(line)
	} catch {
		// Not JSON — pass through as-is (e.g. docker build output)
		return line
	}

	const type = event.type as string

	if (type === "system" && event.subtype === "init") {
		const model = (event as Record<string, unknown>).model as string
		return `${BOLD}${CYAN}[init]${RESET}\n\tmodel=${model}`
	}

	if (type === "assistant") {
		const msg = event.message as Record<string, unknown>
		const content = msg?.content as Array<Record<string, unknown>>
		if (!content) return null

		const parts: string[] = []
		for (const block of content) {
			if (block.type === "tool_use" && TODO_TOOLS.has(block.name as string)) {
				suppressedIds.add(block.id as string)
				continue
			}
			if (block.type === "tool_use" && QUIET_TOOLS.has(block.name as string)) {
				suppressedIds.add(block.id as string)
			}
			if (block.type === "thinking") {
				const thinking = block.thinking as string
				if (thinking) {
					parts.push(`${DIM}[think]${RESET}\n${DIM}${indent(thinking)}${RESET}`)
				}
			} else if (block.type === "tool_use") {
				const name = block.name as string
				const input = block.input as Record<string, unknown>
				if (name === "Bash") {
					parts.push(
						`${YELLOW}[${name}]${RESET}\n${indent(input.command as string)}`,
					)
				} else if (name === "Read") {
					parts.push(
						`${YELLOW}[${name}]${RESET} ${input.file_path as string}`,
					)
				} else if (name === "Edit") {
					parts.push(
						`${YELLOW}[${name}]${RESET} ${input.file_path as string}`,
					)
				} else if (name === "Write") {
					parts.push(
						`${YELLOW}[${name}]${RESET} ${input.file_path as string}`,
					)
				} else if (name === "Grep") {
					parts.push(
						`${YELLOW}[${name}]${RESET}\n\t/${input.pattern as string}/`,
					)
				} else if (name === "Glob") {
					parts.push(
						`${YELLOW}[${name}]${RESET}\n\t${input.pattern as string}`,
					)
				} else if (name === "Agent") {
					parts.push(
						`${YELLOW}[${name}]${RESET} ${input.description as string} (${input.subagent_type as string})`,
					)
				} else {
					parts.push(
						`${YELLOW}[${name}]${RESET}\n\t${JSON.stringify(input)}`,
					)
				}
			} else if (block.type === "text") {
				parts.push(`${GREEN}[text]${RESET}\n${indent(block.text as string)}`)
			}
		}
		return parts.length > 0 ? parts.join("\n") : null
	}

	if (type === "user") {
		const msg = event.message as Record<string, unknown>
		const content = msg?.content as Array<Record<string, unknown>>
		if (!content) return null

		for (const block of content) {
			if (block.type === "tool_result" && suppressedIds.has(block.tool_use_id as string)) {
				continue
			}
			if (block.type === "tool_result") {
				const raw = block.content
				const result = collapseCodeBlocks(
					typeof raw === "string"
						? raw
						: Array.isArray(raw)
							? (raw as Array<Record<string, unknown>>)
								.filter((b) => b.type === "text")
								.map((b) => b.text as string)
								.join("\n")
							: JSON.stringify(raw),
				)
				if (block.is_error) {
					return `${RED}[error]${RESET}\n${indent(result)}`
				}
				if (result) {
					return `${DIM}[result]${RESET}\n${DIM}${result}${RESET}`
				}
			}
		}
		return null
	}

	if (type === "result") {
		const result = event.result as string
		const cost = event.total_cost_usd as number
		const turns = event.num_turns as number
		const summary = result || "(no summary)"
		return `\n${BOLD}${GREEN}[done]${RESET}\n\tturns=${turns} cost=$${cost?.toFixed(4) ?? "?"}\n${indent(summary)}`
	}

	return null
}

const decoder = new TextDecoder()
const reader = Bun.stdin.stream().getReader()
let buffer = ""

while (true) {
	const { done, value } = await reader.read()
	if (done) break

	buffer += decoder.decode(value, { stream: true })
	const lines = buffer.split("\n")
	buffer = lines.pop() ?? ""

	for (const line of lines) {
		if (!line.trim()) continue
		const formatted = formatEvent(line.trim())
		if (formatted) console.log(formatted)
	}
}

// Flush remaining buffer
if (buffer.trim()) {
	const formatted = formatEvent(buffer.trim())
	if (formatted) console.log(formatted)
}
