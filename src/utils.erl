-module(utils).

-export([load_config/0]).

-include_lib("atomic_register/include/ar_def.hrl").

load_config() ->
    {ok, Nodes} = application:get_env(nodes),
    Majority = ceil(length(Nodes) / 2),
    {Majority, Nodes}.

ceil(X) when X < 0 ->
    trunc(X);
ceil(X) ->
    T = trunc(X),
    case X - T == 0 of
	true -> T;
	false -> T + 1
    end.
	    
