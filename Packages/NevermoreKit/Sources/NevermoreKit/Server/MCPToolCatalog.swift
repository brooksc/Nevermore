import Foundation

/// One MCP tool: what the client is told about it, and which route it forwards
/// to.
public struct MCPToolDefinition: Sendable, Hashable {
    public let name: String
    public let description: String
    /// The JSON Schema for the tool's arguments, as a JSON object literal.
    ///
    /// A string rather than a Swift structure because it goes onto the wire
    /// verbatim: building it out of dictionaries would mean writing an encoder
    /// for a shape that is already JSON, and the schema is easier to read and to
    /// review as the JSON it is. The tests parse every one of them, so a typo
    /// fails the suite rather than the client.
    public let schemaJSON: String
    /// The `/mcp/...` path this tool posts to.
    public let path: String

    public init(name: String, description: String, schemaJSON: String, path: String) {
        self.name = name
        self.description = description
        self.schemaJSON = schemaJSON
        self.path = path
    }
}

/// The read-only tool surface an MCP client sees.
///
/// It lives in NevermoreKit rather than in the bridge executable so the harness
/// can hold it to its promises: that every description states message bodies are
/// unavailable, that every schema is valid JSON, and that every tool points at a
/// route the server actually serves. A catalog inside `main.swift` would be
/// unreachable from a test — jobhunt's is, and its descriptions have drifted
/// from its routes more than once.
public enum MCPToolCatalog {
    /// Appended to every description. Repeated per tool rather than stated once
    /// in the server info because clients show tool descriptions individually
    /// and an agent may only ever see the one it is about to call.
    public static let bodiesCaveat =
        "Message bodies are unavailable: Nevermore syncs headers only, and never "
        + "downloads message content. Classify from sender, domain, subject lines, "
        + "dates and read rate."

    /// Appended to every description too — the account rule is the other thing
    /// an agent will otherwise assume its way past.
    public static let accountCaveat =
        "Serves the account currently open in Nevermore, named in every response; "
        + "there is no account switching over MCP. The app must be running, and "
        + "the tools refuse while it is in demo mode."

    public static let tools: [MCPToolDefinition] = [
        MCPToolDefinition(
            name: "list_senders",
            description: """
                List bulk-mail senders in one of Nevermore's collections, with the \
                filters that make a thousand-sender mailbox tractable: message count, \
                unread percentage, when they last wrote, how they can be unsubscribed \
                from, whether they are a mailing list, and any classification or \
                context label a previous session recorded. Paged — the default limit \
                is \(MCPRoutes.defaultLimit) and the maximum is \(MCPRoutes.maxLimit); \
                read `has_more` and pass `next_offset` rather than assuming one call \
                returned everything.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "collection": {
                      "type": "string",
                      "enum": ["all_senders", "reappeared", "unsubscribed", "ignored"],
                      "default": "all_senders",
                      "description": "all_senders is the working list. unsubscribed is where a sender goes once an unsubscribe was recorded; reappeared is those who kept mailing anyway; ignored is hidden on this Mac only."
                    },
                    "limit": {"type": "integer", "default": \(MCPRoutes.defaultLimit), "minimum": 1, "maximum": \(MCPRoutes.maxLimit)},
                    "offset": {"type": "integer", "default": 0, "minimum": 0},
                    "min_messages": {"type": "integer", "description": "Keeps senders with at least this many messages stored."},
                    "max_messages": {"type": "integer"},
                    "min_unread_percent": {"type": "number", "minimum": 0, "maximum": 100, "description": "Read rate is the strongest signal available: a sender at 100% unread is one nobody opens."},
                    "max_unread_percent": {"type": "number", "minimum": 0, "maximum": 100},
                    "received_after": {"type": "string", "description": "ISO-8601 timestamp or YYYY-MM-DD, matched against the sender's most recent message."},
                    "received_before": {"type": "string"},
                    "unsubscribe_method": {
                      "type": "string",
                      "enum": ["one_click", "web", "mailto", "none"],
                      "description": "How this sender can be unsubscribed from, known from stored headers without attempting anything. one_click is an RFC 8058 POST; web is a plain link; mailto is an unsubscribe email; none means they published no machine-readable target."
                    },
                    "needs_browser": {"type": "boolean", "description": "True for senders nothing automated can finish — no machine-readable target, or they already ignored an unsubscribe."},
                    "is_mailing_list": {"type": "boolean", "description": "True for RFC 2919 discussion or notification lists, as opposed to marketing blasts."},
                    "classification": {"type": "string", "description": "Exact match on a classification a previous session recorded."},
                    "context": {"type": "string", "description": "Exact match on a context label, e.g. job-search-2026."}
                  }
                }
                """,
            path: "/mcp/senders/list"),

        MCPToolDefinition(
            name: "get_sender",
            description: """
                One sender in full: every address in the group, the parsed \
                List-Unsubscribe targets, whether the sender supports RFC 8058 \
                one-click, what unsubscribe was already attempted and whether they \
                mailed since, any recorded classification, and the most recent \
                subject lines.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["sender_id"],
                  "properties": {
                    "sender_id": {"type": "string", "description": "The id from list_senders, e.g. domain:acme.com or address:news@acme.com."},
                    "limit": {"type": "integer", "default": \(MCPRoutes.defaultLimit), "maximum": \(MCPRoutes.maxLimit), "description": "How many recent subject lines to include."}
                  }
                }
                """,
            path: "/mcp/senders/get"),

        MCPToolDefinition(
            name: "list_messages",
            description: """
                Subject lines and dates for one sender, newest first, paged. This is \
                the finest grain of content that exists locally.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["sender_id"],
                  "properties": {
                    "sender_id": {"type": "string"},
                    "limit": {"type": "integer", "default": \(MCPRoutes.defaultLimit), "minimum": 1, "maximum": \(MCPRoutes.maxLimit)},
                    "offset": {"type": "integer", "default": 0, "minimum": 0}
                  }
                }
                """,
            path: "/mcp/senders/messages"),

        MCPToolDefinition(
            name: "search_senders",
            description: """
                Case-insensitive substring search across sender display names, \
                addresses, domains and subject lines, over every collection — so it \
                will also find senders already unsubscribed from or ignored. Paged.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["query"],
                  "properties": {
                    "query": {"type": "string"},
                    "limit": {"type": "integer", "default": \(MCPRoutes.defaultLimit), "minimum": 1, "maximum": \(MCPRoutes.maxLimit)},
                    "offset": {"type": "integer", "default": 0, "minimum": 0}
                  }
                }
                """,
            path: "/mcp/senders/search"),

        MCPToolDefinition(
            name: "unsubscribe_history",
            description: """
                Every unsubscribe Nevermore has recorded, newest first. An outcome of \
                'requested' means the request was accepted, not that the sender \
                honoured it — only `reappeared` is evidence either way. Records \
                survive after a sender's messages are gone.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "outcome": {"type": "string", "enum": ["requested", "confirmed", "failed"]},
                    "limit": {"type": "integer", "default": \(MCPRoutes.defaultLimit), "minimum": 1, "maximum": \(MCPRoutes.maxLimit)},
                    "offset": {"type": "integer", "default": 0, "minimum": 0}
                  }
                }
                """,
            path: "/mcp/unsubscribe/history"),

        MCPToolDefinition(
            name: "list_reappeared",
            description: """
                Senders who kept mailing after an unsubscribe was recorded, worst \
                first by how many messages arrived since. These are the ones the \
                automated path failed on; finishing them needs a human in a browser.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "limit": {"type": "integer", "default": \(MCPRoutes.defaultLimit), "minimum": 1, "maximum": \(MCPRoutes.maxLimit)},
                    "offset": {"type": "integer", "default": 0, "minimum": 0}
                  }
                }
                """,
            path: "/mcp/senders/reappeared"),

        MCPToolDefinition(
            name: "mailbox_summary",
            description: """
                Orientation without pulling rows: how many senders and messages, how \
                they split across collections and unsubscribe methods, how many need a \
                browser, how many carry a recorded decision, and which context labels \
                exist. Call this first.
                """,
            schemaJSON: """
                {"type": "object", "properties": {}}
                """,
            path: "/mcp/mailbox/summary"),

        MCPToolDefinition(
            name: "sync_status",
            description: """
                When Nevermore last synced and how much it holds. Nevermore only ever \
                syncs messages carrying a List-Unsubscribe header, so these counts \
                describe the mailbox's bulk mail, not the mailbox.
                """,
            schemaJSON: """
                {"type": "object", "properties": {}}
                """,
            path: "/mcp/sync/status"),

        MCPToolDefinition(
            name: "list_by_context",
            description: """
                Every sender decided under one context label, e.g. job-search-2026 — \
                the cohort query that lets a whole situation be reopened at once when \
                it ends. Labels are matched exactly and never interpreted; \
                mailbox_summary lists the ones in use. A null sender means the \
                decision's address has no messages left locally, which the decision \
                deliberately outlives.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["context"],
                  "properties": {
                    "context": {"type": "string", "description": "The exact label, as recorded. See mailbox_summary.contexts."}
                  }
                }
                """,
            path: "/mcp/decisions/by-context"),

        // MARK: - Writes (TASK-46)
        //
        // Narrow on purpose. The agent classifies and proposes; the human
        // actuates. Every tool that reaches a sender's mailbox or a third party
        // returns `awaiting_confirmation` and does nothing until a person says
        // so, and there is no bulk unsubscribe here at all — see get_policy.

        MCPToolDefinition(
            name: "propose_selection",
            description: """
                Put a set of senders in front of the human for review, each with \
                your reason for proposing it. This is the primary write path and the \
                only route to acting on more than one sender: Nevermore shows them in \
                a Proposed collection with your reasons in the rows, and the person \
                decides. Capped at \(SenderProposal.maxItems) senders — send your best \
                \(SenderProposal.maxItems) rather than everything, and read `dropped` \
                and `truncated` in the response, because the human only ever sees what \
                survived the cap. Nothing happens to any sender when you call this. A \
                reason is required for every sender: a row nobody can see a reason for \
                can only be rubber-stamped, which defeats the review.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["senders"],
                  "properties": {
                    "summary": {"type": "string", "description": "One line saying what this proposal is, e.g. 'senders from the 2026 job search'. Shown above the list."},
                    "senders": {
                      "type": "array",
                      "maxItems": \(SenderProposal.maxItems),
                      "items": {
                        "type": "object",
                        "required": ["sender_id", "reason"],
                        "properties": {
                          "sender_id": {"type": "string", "description": "The id from list_senders."},
                          "reason": {"type": "string", "description": "One line, in your own words, shown verbatim in the row. This is what makes your judgement checkable."}
                        }
                      }
                    }
                  }
                }
                """,
            path: "/mcp/proposal/create"),

        MCPToolDefinition(
            name: "get_proposal_status",
            description: """
                What became of the proposal: still under review, edited (the human \
                took senders out — the clearest signal your judgement was wrong about \
                those rows), or dismissed. Reports per-sender outcomes for anything \
                that has actually happened, each carrying Nevermore's own distinction \
                between confirmed, requested, failed and needs_manual. 'requested' \
                means the request was accepted, never that the sender honoured it — \
                do not report it as unsubscribed. The ledger is per app run, so a \
                relaunch empties it; the durable record is unsubscribe_history.
                """,
            schemaJSON: """
                {"type": "object", "properties": {}}
                """,
            path: "/mcp/proposal/status"),

        MCPToolDefinition(
            name: "unsubscribe",
            description: """
                Ask Nevermore to unsubscribe from ONE sender. It opens the app's \
                confirmation in front of the user and returns awaiting_confirmation \
                having done nothing — no request has been sent when this call \
                returns, and the answer may be no. Read `warnings`: unsubscribing \
                tells the sender the address is live and read, which is worth \
                nothing against a legitimate mailing list and worth something to a \
                spammer. For several senders use propose_selection; there is no bulk \
                unsubscribe and asking for one here is refused.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["sender_id"],
                  "properties": {
                    "sender_id": {"type": "string", "description": "The id from list_senders. One sender; a list is refused."}
                  }
                }
                """,
            path: "/mcp/senders/unsubscribe"),

        MCPToolDefinition(
            name: "ignore",
            description: """
                Hide a sender from the working list without unsubscribing from \
                anything. Local to this Mac, reversible with unignore, and invisible \
                to the sender — which makes it the right answer whenever keeping the \
                mail is fine and it is only the clutter that is the problem. Runs \
                without asking the user. Per-sender results.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "sender_ids": {"type": "array", "items": {"type": "string"}},
                    "sender_id": {"type": "string", "description": "Convenience for a single sender."}
                  }
                }
                """,
            path: "/mcp/senders/ignore"),

        MCPToolDefinition(
            name: "unignore",
            description: """
                Put ignored senders back in the working list. The exact reverse of \
                ignore, and just as local. Per-sender results.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "properties": {
                    "sender_ids": {"type": "array", "items": {"type": "string"}},
                    "sender_id": {"type": "string"}
                  }
                }
                """,
            path: "/mcp/senders/unignore"),

        MCPToolDefinition(
            name: "set_classification",
            description: """
                Record what you decided about a sender and why, so a later session \
                does not have to re-derive it. The classification is your own label, \
                stored verbatim and never interpreted by Nevermore; the context label \
                is the situation the decision was contingent on (e.g. \
                job-search-2026), which is what makes 'that is over, what can go now' \
                answerable later through list_by_context. Recording a decision does \
                nothing to the sender's mail. One decision per address — a later call \
                supersedes the earlier judgement.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["sender_id", "classification", "reason"],
                  "properties": {
                    "sender_id": {"type": "string"},
                    "classification": {"type": "string", "description": "Your label, e.g. keep, expired-situation, marketing."},
                    "reason": {"type": "string", "description": "Why, in one line. A later session reads this instead of guessing."},
                    "context": {"type": "string", "description": "The situation this was contingent on, matched exactly later, e.g. job-search-2026."}
                  }
                }
                """,
            path: "/mcp/senders/classify"),

        MCPToolDefinition(
            name: "trash_sender_messages",
            description: """
                Ask to move one sender's messages to the mail provider's Trash. \
                Destructive, so it ALWAYS puts a confirmation in front of the user \
                and returns awaiting_confirmation having moved nothing — there is no \
                argument, setting or policy that skips this, including the user's own \
                trash-confirmation threshold. Trashing does not unsubscribe: the \
                sender keeps mailing, and the new mail keeps arriving.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["sender_id"],
                  "properties": {
                    "sender_id": {"type": "string"}
                  }
                }
                """,
            path: "/mcp/senders/trash"),

        MCPToolDefinition(
            name: "start_sync",
            description: """
                Ask Nevermore to fetch new message headers now. Returns as soon as \
                the sync starts, not when it finishes — poll sync_status. A sync \
                already in progress is left alone rather than restarted.
                """,
            schemaJSON: """
                {"type": "object", "properties": {}}
                """,
            path: "/mcp/sync/start"),

        MCPToolDefinition(
            name: "set_grouping",
            description: """
                Correct how one sender's mail is grouped: split a domain into its \
                separate addresses when they are really different senders, or keep \
                the domain as one row. Affects display and what an unsubscribe acts \
                on; it never touches the mail, and recorded decisions survive it \
                because they are keyed by address rather than by group.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["sender_id", "mode"],
                  "properties": {
                    "sender_id": {"type": "string"},
                    "mode": {"type": "string", "enum": ["split_by_address", "keep_as_one"]}
                  }
                }
                """,
            path: "/mcp/senders/grouping"),

        MCPToolDefinition(
            name: "forget_unsubscribe_record",
            description: """
                Drop Nevermore's record that a sender was unsubscribed from, moving \
                them back into the working list. The record is the app's only memory \
                that the unsubscribe happened, and forgetting it does not undo \
                anything with the sender — the next unsubscribe is a real second \
                request. Local and reversible in the app for a moment afterwards.
                """,
            schemaJSON: """
                {
                  "type": "object",
                  "required": ["sender_id"],
                  "properties": {
                    "sender_id": {"type": "string"}
                  }
                }
                """,
            path: "/mcp/unsubscribe/forget"),

        MCPToolDefinition(
            name: "get_policy",
            description: """
                What you may do unattended and what needs the human, so you can plan \
                a session instead of discovering the walls mid-batch. The short \
                version: everything local and reversible runs on its own; anything \
                that reaches the mailbox or a third party asks the user first; and \
                there is no bulk unsubscribe over MCP and will not be one — bulk goes \
                through propose_selection and a human confirming that exact set in \
                the app. Answers whether or not a mailbox is open.
                """,
            schemaJSON: """
                {"type": "object", "properties": {}}
                """,
            path: "/mcp/policy"),
    ]

    /// The description a client is shown: the tool's own text plus the two
    /// caveats every tool carries.
    public static func fullDescription(of tool: MCPToolDefinition) -> String {
        "\(tool.description)\n\n\(bodiesCaveat)\n\n\(accountCaveat)"
    }

    public static func tool(named name: String) -> MCPToolDefinition? {
        tools.first { $0.name == name }
    }
}
