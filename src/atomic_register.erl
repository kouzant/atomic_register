-module(atomic_register).

-behaviour(gen_server).

%% Public API
-export([start/0, start_link/0, write/2]).

%% Server API
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% write_attempt: {Key, Value, num_of_resp, seqs}
%% store: key, value, sequence number
-record(reg_state, {write_attempt :: {string(), string(), integer(), [integer()]},
		    store :: [{string(), string(), integer()}]
		   }).

-define(REG_NAME, ar).

%% Public API
start() ->
    gen_server:start({local, ?REG_NAME}, ?MODULE, [], []).

start_link() ->
    gen_server:start_link({local, ?REG_NAME}, ?MODULE, [], []).

write(Key, Value) ->
    gen_server:cast(?REG_NAME, {ar_write_init, Key, Value}).

%% Callback functions
init(_Args) ->
    InitState = #reg_state{store=[]},
    {ok, InitState}.

terminate(normal, _State) ->
    ok;
terminate(Reason, _State) ->
    io:format("Atomic register ubnormal termination ~p~n", [Reason]).

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

handle_info(Info, State) ->
    io:format("Atomic register wtf??? ~p~n", [Info]),
    {noreply, State}.

handle_call(_Msg, _From, State) ->
    {reply, reply, State}.

handle_cast({ar_write_init, Key, Value}, State) ->
    %% Read from majority to get highest sequence number for that key
    beb:broadcast({ar_seq, Key, self()}),
    
    {noreply, State};

%% Wait for majority
handle_cast({ar_seq_reply, Key, Seq}, State) ->
    io:format("Received sequence number: ~p~n", [Seq]),
    %% If num of sequence numbers received >= majority
    %% continue with the second phase
    {noreply, State};

handle_cast({ar_seq, Key, From}, State) ->
    Store = State#reg_state.store,
    case get_value(Key, Store) of
	{ok, {_Key, _Value, Seq}} ->
	    gen_server:cast(From, {ar_seq_reply, Key, Seq});
	{not_found} ->
	    gen_server:cast(From, {ar_seq_reply, Key, 0})
    end,
    {noreply, State}.

%% Private functions
get_value(Key, [{Key, Value, Seq} | _Xs]) ->
    {ok, {Key, Value, Seq}};
get_value(Key, [{_, _, _} | Xs]) ->
    get_value(Key, Xs);
get_value(_Key, []) ->
    {not_found}.

