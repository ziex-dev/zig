-module(zig_test).
-export([add/2]).
-on_load(init/0).

init() ->
    Path = "./zig_test",
    io:format("Loading NIF from: ~s~n", [Path]),
    case erlang:load_nif(Path, 0) of
        ok -> 
            io:format("NIF loaded successfully!~n"),
            ok;
        {error, {reload, _}} ->
            io:format("NIF already loaded~n"),
            ok;
        Error ->
            io:format("Failed to load NIF: ~p~n", [Error]),
            Error
    end.

add(_A, _B) ->
    erlang:nif_error(nif_not_loaded).
