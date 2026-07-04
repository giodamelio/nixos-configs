# Thin stub: agevault's `__complete` backend computes every candidate level
# (subcommands, then dynamic host and secret names). We pass only the
# already-completed words; fish filters by the typed prefix and shows the
# tab-separated descriptions. Logic lives in agevault.nu, never here.
function __agevault_complete
    set -l toks (commandline -opc)
    set -e toks[1]
    for line in (agevault __complete $toks 2>/dev/null)
        test "$line" = '%files'; and continue
        echo $line
    end
end

complete -c agevault -f -a '(__agevault_complete)'
