-module(atomic_register).

-behaviour(gen_server).

-include_lib("atomic_register/include/ar_def.hrl").

%% Public API
-export([start/0, start_link/1, write/3, read/2]).

%% Server API
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% write_attempt: {Key, Value, num_of_resp, seqs}
%% read_attempt: {Key, num_of_resp, [{value, seq}]}
%% state when writing: init -> w_seq_reply -> write_phase -> init
%% state when reading: init -> r_seq_reply -> write_phase -> init
%% store: key, value, sequence number
%% majority: the majority of the quorum
-record(reg_state, {write_attempt :: {string(), string(), integer(), [integer()]},
		    read_attempt :: {string(), integer(), [{string(), integer()}]},
		    state :: atom(),
		    store :: [{string(), string(), integer()}],
		    client :: {pid(), reference()},
		    majority :: integer()
		   }).

%% Public API
start() ->
    gen_server:start({local, ?REG_NAME}, ?MODULE, [], []).

start_link(Majority) ->
    gen_server:start_link({local, ?REG_NAME}, ?MODULE, Majority, []).

write(Key, Value, Client) ->
    gen_server:cast(?REG_NAME, {ar_write_init, Key, Value, Client}).

read(Key, Client) ->
    gen_server:cast(?REG_NAME, {ar_read_init, Key, Client}).

%% Callback functions
init(Majority) ->
    InitState = #reg_state{state = init, majority = Majority, store = [], client = {}},
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

handle_cast({ar_read_init, Key, Client}, State) ->
    %% Read value from majority
    beb:broadcast({ar_seq, Key, self()}),
    Attempt = {Key, 0, []},
    NewState = State#reg_state{state=r_seq_reply, read_attempt = Attempt, client = Client},
    {noreply, NewState};
       
handle_cast({ar_write_init, Key, Value, Client}, State) ->
    %% Read from majority to get highest sequence number for that key
    beb:broadcast({ar_seq, Key, self()}),
    %% Init the state for this write attempt
    Attempt = {Key, Value, 0, []},
    NewState = State#reg_state{state=w_seq_reply, write_attempt = Attempt, client=Client},
    {noreply, NewState};

handle_cast({ar_seq, Key, From}, State) ->
    Store = State#reg_state.store,
    case get_value(Key, Store) of
	{ok, {_Key, Value, Seq}} ->
	    gen_server:cast(From, {ar_seq_reply, Key, Value, Seq});
	{not_found} ->
	    gen_server:cast(From, {ar_seq_reply, Key, null, 0})
    end,
    {noreply, State};

%% Wait for majority
handle_cast({ar_seq_reply, Key, _RecvValue, Seq}, State)
  when State#reg_state.state =:= w_seq_reply ->
    Majority = State#reg_state.majority,
    {Key, Value, Resps, Seqs} = State#reg_state.write_attempt,
    %% If num of sequence numbers received >= majority
    %% continue with the second phase
    NewSeqs = [Seq | Seqs],
    case Resps + 1 < Majority of
	true ->
	    {noreply, State#reg_state{write_attempt={Key, Value, Resps + 1, NewSeqs}}};
	false ->
	    %% Continue with the second phase
	    Sequence = lists:max(NewSeqs) + 1,
	    gen_server:cast(?REG_NAME, {ar_write_phase, Key, Value, Sequence}),
	    {noreply, State#reg_state{state=write_phase}}
    end;

handle_cast({ar_seq_reply, Key, RecvValue, Seq}, State)
  when State#reg_state.state =:= r_seq_reply ->
    Majority = State#reg_state.majority,
    {Key, Resps, RecvValues} = State#reg_state.read_attempt,
    NewRecvValues = [{RecvValue, Seq} | RecvValues],
    case Resps + 1 < Majority of
	true ->
	    {noreply, State#reg_state{read_attempt = {Key, Resps + 1, NewRecvValues}}};
	false ->
	    [{V, S} | _] = lists:reverse(lists:ukeysort(2, NewRecvValues)),
	    NewState = handle_read_majority(Key, V, S, State),
	    {noreply, NewState}
    end;

handle_cast({ar_seq_reply, _, _, _}, State) ->
    {noreply, State};

handle_cast({ar_write_phase, Key, Value, Sequence}, State)
  when State#reg_state.state =:= write_phase->
    %% bcast and wait for majority for the write request
    beb:broadcast({ar_write_req_quorum, Key, Value, Sequence, self()}),
    %% Update the record if present
    {noreply, State#reg_state{write_attempt={Key, Value, 0, []}}};

handle_cast({ar_write_req_quorum, Key, Value, Sequence, From}, State) ->
    Store = State#reg_state.store,
    case get_value(Key, Store) of
	{ok, {Key, _Value, Seq}} when Sequence > Seq ->
	    NewStore = lists:keyreplace(Key, 1, Store, {Key, Value, Sequence}),
	    gen_server:cast(From, {ar_write_req_quorum_ack}),
	    {noreply, State#reg_state{store=NewStore}};
	{ok, {Key, _Value, Seq}} when Sequence =< Seq->
	    gen_server:cast(From, {ar_write_req_quorum_ack}),
	    {noreply, State};
	{not_found} ->
	    NewStore = [{Key, Value, Sequence} | Store],
	    gen_server:cast(From, {ar_write_req_quorum_ack}),
	    {noreply, State#reg_state{store=NewStore}}
    end;

handle_cast({ar_write_req_quorum_ack}, State) when State#reg_state.state =:= write_phase ->
    Majority = State#reg_state.majority,
    {K, V, Resps, S} = State#reg_state.write_attempt,
    case Resps + 1 < Majority of
	true ->
	    {noreply, State#reg_state{write_attempt={K, V, Resps + 1, S}}};
	false ->
	    {Pid, Ref} = State#reg_state.client,
	    Pid ! {ar_attempt_complete, Ref, K, V},
	    {noreply, State#reg_state{state=init, write_attempt={}, read_attempt={}}}
    end;

handle_cast({ar_write_req_quorum_ack}, State) ->
    {noreply, State}.
	    
%% Private functions
get_value(Key, [{Key, Value, Seq} | _Xs]) ->
    {ok, {Key, Value, Seq}};
get_value(Key, [{_, _, _} | Xs]) ->
    get_value(Key, Xs);
get_value(_Key, []) ->
    {not_found}.

handle_read_majority(Key, null, _Seq, State) ->
    {Pid, Ref} = State#reg_state.client,
    Pid ! {ar_read_not_found, Ref, Key},
    State#reg_state{state=init, read_attempt={}};

handle_read_majority(Key, Value, Seq, State) ->
    gen_server:cast(?REG_NAME, {ar_write_phase, Key, Value, Seq}),
    State#reg_state{state=write_phase}.

