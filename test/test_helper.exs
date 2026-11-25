# Mox.defmock definitions for external API clients go here.
Mox.defmock(Dirmoon.LLMMock, for: Dirmoon.LLM)
Mox.defmock(Dirmoon.DataForSEOMock, for: Dirmoon.DataForSEO)
Mox.defmock(Dirmoon.SearchConsoleMock, for: Dirmoon.SearchConsole.Client)
Mox.defmock(Dirmoon.WebPageMock, for: Dirmoon.WebPage)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Dirmoon.Repo, :manual)
