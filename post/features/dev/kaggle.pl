%% dev/kaggle — Kaggle CLI for the demo pipelines (kaggle-run in the
%% Makefile). Default deps chain it behind uv. Credentials are manual
%% (~/.kaggle/kaggle.json) under the no-keyring policy.

user_tool(kaggle, '.local/bin/kaggle', 'uv tool install kaggle').
