# mode="fast" (target-cpu=<march> + opt-level=3 + codegen-units=1) is
# not just the generic "go fast" default here - it was actually measured
# against this exact binary (a real phi-4 GGUF summarize+title job):
# generation time dropped from ~141s (mode="default", i.e. no codegen-
# units=1) to ~92.5s (mode="fast") on the same machine. Given CPU
# inference is the dominant cost for this tool, "fast" is the
# specifically-justified choice, not a shortcut.
{
  textinfer = { mode = "fast"; lang = "rust"; scope = "global"; };
}
