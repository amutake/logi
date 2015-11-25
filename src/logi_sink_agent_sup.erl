%% @copyright 2014-2015 Takeru Ohta <phjgt308@gmail.com>
%%
%% @doc TODO
%% @private
-module(logi_sink_agent_sup).

-behaviour(supervisor).

%%----------------------------------------------------------------------------------------------------------------------
%% Exported API
%%----------------------------------------------------------------------------------------------------------------------
-export([start_link/1]).
-export([start_agent/2]).
-export([get_child_agent_set_sup/1]).

%%----------------------------------------------------------------------------------------------------------------------
%% 'supervisor' Callback API
%%----------------------------------------------------------------------------------------------------------------------
-export([init/1]).

%%----------------------------------------------------------------------------------------------------------------------
%% Exported Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @doc Starts a supervisor
-spec start_link(supervisor:sup_flags()) -> {ok, pid()} | {error, Reason::term()}.
start_link(Flags) ->
    supervisor:start_link(?MODULE, [Flags]).

-spec get_child_agent_set_sup(pid()) -> pid().
get_child_agent_set_sup(Sup) ->
    [ChildAgentSetSup] = [Pid || {child_agent_set_sup, Pid, _, _} <- supervisor:which_children(Sup), is_pid(Pid)],
    ChildAgentSetSup.

-spec start_agent(pid(), supervisor:child_spec()) -> {ok, pid()} | {error, Reason::term()}.
start_agent(Sup, ChildSpec) ->
    case supervisor:start_child(Sup, ChildSpec) of
        {error, Reason} -> {error, Reason};
        {ok, undefined} -> {error, {ignored, ChildSpec}};
        {ok, Pid}       -> {ok, Pid}
    end.

%%----------------------------------------------------------------------------------------------------------------------
%% 'supervisor' Callback Functions
%%----------------------------------------------------------------------------------------------------------------------
%% @private
init([Flags]) ->
    ChildrenSup = #{id => child_agent_set_sup, start => {logi_sink_agent_set_sup, start_link, []}, type => supervisor},
    {ok, {Flags, [ChildrenSup]}}.
