# const TERMINAL_BACKGROUND = Ref(:dark)

"""
    guess_terminal_background()

Guess whether the current terminal background is "light" or "dark",
returning one of those symbols. If unable to detect, assumes dark.

Used to initially set `TERMINAL_BACKGROUND`.
"""
function guess_terminal_background()
    if Base.get_bool_env("TERM_LIGHT", false)
        return :light
    end
    bg_color = read_osc_11() |> interpret_osc_11
    if !isnothing(bg_color)
        r, g, b = bg_color
        luminescence = 0.299 * r + 0.587 * g + 0.144 * b
        ifelse(luminance < 0.5, :dark, :light)
    else
        :unknown
    end
end

function read_osc_11(timeout::Real = 0.05)
    set_tty_raw!(stdin, true)
    outbytes = UInt8[]
    start = time()
    lock(stdin.cond)
    Base.iolock_begin()
    while start - time() < timeout && (isempty(outbytes) || last(outbytes) ∉ (UInt8('\\'), UInt8('\a')))
        if bytesavailable(stdin.buffer) > 0
            push!(outbytes, read(stdin.buffer, UInt8))
        else
            stdin.readerror === nothing || throw(stdin.readerror)
            isopen(stdin) || break
            Base.start_reading(stdin) # ensure we are reading
            Base.iolock_end()
            @info "Waiting for stdin.cond"
            wait(stdin.cond)
            @info "Finished for stdin.cond"
            unlock(stdin.cond)
            Base.iolock_begin()
            lock(stdin.cond)
        end
    end
    Base.iolock_end()
    unlock(stdin.cond)
    set_tty_raw!(stdin, false)
    String(outbytes)
end

function interpret_osc_11(output::String)
    if startswith(output, "\e]11;")
        output = @view output[ncodeunits("\e]11;")+1:end]
    end
    if endswith(output, "\e\\")
        output = @view output[begin:end-2]
    else endswith(output, "\a")
        output = @view output[begin:end-1]
    end
    if startswith(output, "rgb:")
        components = split(output[ncodeunits("rgb:")+1:end], '/')
        length(components) == 3 || return
    elseif startswith(output, "rgba:")
        components = split(output[ncodeunits("rgba:")+1:end], '/')
        length(components) == 4 || return
        components = components[1:3]
    else
        return
    end
    validcolorhex(chex) =
        !isempty(chex) && all(c -> c in vcat('0':'9', 'a':'f', 'A':'F'), chex)
    all(validcolorhex, components) || return
    map(chex -> parse(Int, chex, base=16) / 16^length(chex), components)
end

# Copied over from `REPL/src/Terminals.jl` with minor modifications.
@static if Sys.iswindows()
    function set_tty_raw!(tty::Base.TTY, raw::Bool)
        is_precompiling[] && return true
        Base.check_open(tty)
        if Base.ispty(tty)
            run((raw ? `stty raw -echo onlcr -ocrnl opost` : `stty sane`), stdin, stdout, stderr)
            true
        else
            ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid},Int32), tty.handle::Ptr{Cvoid}, raw) != -1
        end
    end
else
    function set_tty_raw!(tty::Base.TTY, raw::Bool)
        Base.check_open(tty)
        ccall(:jl_tty_set_mode, Int32, (Ptr{Cvoid},Int32), tty.handle::Ptr{Cvoid}, raw) != -1
    end
end
