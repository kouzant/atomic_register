-module(client).

-export([write/2]).

write(Key, Value) ->
    Ref = erlang:make_ref(),
    atomic_register:write(Key, Value, {self(), Ref}),
    io:format("Writing pair {~p, ~p}~n)", [Key, Value]),
    receive
	{ar_write_complete, Ref} ->
	    io:format("Pair has been written to register ~n")
    end.
			  
