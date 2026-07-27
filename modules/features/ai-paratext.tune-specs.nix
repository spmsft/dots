# mode="fast" (target-cpu=<march> + opt-level=3 + codegen-units=1) is
# not just the generic "go fast" default here - it was measured against
# the earlier mistralrs-based binary (a real phi-4 GGUF summarize+title
# job): generation time dropped from ~141s (mode="default", i.e. no
# codegen-units=1) to ~92.5s (mode="fast") on the same machine. Given
# inference is the dominant cost for this tool, "fast" is kept as the
# specifically-justified choice for the candle rewrite too, though the
# absolute numbers above predate it and haven't been re-measured.
{
  paratext = { mode = "fast"; lang = "rust"; scope = "global"; };
}
