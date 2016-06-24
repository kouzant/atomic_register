-module(client).

-export([write/2, read/1]).

write(Key, Value) ->
    Ref = erlang:make_ref(),
    atomic_register:write(Key, Value, {self(), Ref}),
    io:format("Writing pair {~p, ~p}~n)", [Key, Value]),
    receive
	{ar_attempt_complete, Ref, K, V} ->
	    io:format("Pair {~p, ~p} has been written to register ~n", [K, V])
    end.

read(Key) ->
    Ref = erlang:make_ref(),
    atomic_register:read(Key, {self(), Ref}),
    receive
	{ar_attempt_complete, Ref, K, V} ->
	    io:format("Value for key ~p is: ~p~n", [K, V])
    end.
			  
