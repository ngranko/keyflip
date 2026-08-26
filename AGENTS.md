Don't put comments in the code that just describe what the next code block does. Comments should explain why, not what. Only put comments in code when the reasoning behind the current implementation should be clarified to not create confusion.

Name functions for their intent, not for the value they produce. They should be verbs describing what they do, not nouns for what they return.

Follow SOLID, DRY and KISS principles in your work. Don't create huge god-files. Soft cap for line count if a single file is 200, if a file grows bigger – consider possible refactors. The same rule should apply for huge functions: if a function grows too large – consider splitting it or moving into its own module if that function is complex enough. Soft line cap for a single function is 20 lines.

Delete unused or obsolete files when your changes make them irrelevant (refactors, feature removals, etc.), and revert files only when the change is yours or explicitly requested. If a git operation leaves you unsure about other agents' in-flight work, stop and coordinate instead of deleting.

Do not write too much code, keep your changes succinct while still fully achieving the required result.
