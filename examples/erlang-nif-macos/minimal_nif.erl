-module(minimal_nif).
-export([test_func/0]).
-on_load(init/0).

init() ->
    io:format("Loading minimal NIF...~n"),
    case erlang:load_nif("./minimal_nif", 0) of
        ok -> 
            io:format("Minimal NIF loaded successfully!~n"),
            ok;
        Error ->
            io:format("Failed to load NIF: ~p~n", [Error]),
            Error
    end.

test_func() ->
    erlang:nif_error(nif_not_loaded).
