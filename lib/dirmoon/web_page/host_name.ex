defmodule Dirmoon.WebPage.HostName do
  @moduledoc """
  The one rule for international host names (`żółw.pl`, `münchen.de`,
  `例え.jp`): dirmoon keeps, requests and compares a host in its ASCII form
  (`xn--w-uga1v8h.pl`), the form DNS and every HTTP connection take, and
  shows it to the owner in its Unicode form.

  The ASCII form comes from UTS #46 processing (the `idna` library), which
  also maps full-width and other compatibility spellings to plain ASCII,
  so `１２７.０.０.１` and `ｌｏｃａｌｈｏｓｔ` become `127.0.0.1` and
  `localhost`. A host already written in ASCII is left as it is. Pure: no
  I/O, and a name the library refuses is `:error`, never an exception.
  """

  @www_prefix "www."
  @ascii_prefix "xn--"
  @idna_options [uts46: true]
  @ascii_only ~r/\A[\x00-\x7F]*\z/

  @doc """
  The ASCII form of `host`: `{:ok, ascii}`, or `:error` for an international
  name that can't be encoded (a label that breaks the IDNA rules, or a name
  longer than 253 bytes once encoded). A host already in ASCII is returned
  unchanged.
  """
  @spec to_ascii(String.t()) :: {:ok, String.t()} | :error
  def to_ascii(host) when is_binary(host) do
    if ascii?(host), do: {:ok, host}, else: encode(host)
  end

  @doc """
  The form two hosts are compared in: the lower-case ASCII form, or the
  name lower-cased when it has none.
  """
  @spec canonical(String.t()) :: String.t()
  def canonical(host) when is_binary(host) do
    case to_ascii(host) do
      {:ok, ascii} -> String.downcase(ascii)
      :error -> String.downcase(host)
    end
  end

  @doc "The canonical form without a leading `www.`: one site under either of its spellings."
  @spec bare(String.t()) :: String.t()
  def bare(host) when is_binary(host), do: host |> canonical() |> String.replace_prefix(@www_prefix, "")

  @doc """
  How `host` reads to the owner: its Unicode form when it holds an encoded
  label that decodes, otherwise as it is (`nil`, for no host, included).
  """
  @spec to_unicode(String.t() | nil) :: String.t() | nil
  def to_unicode(host) when is_binary(host) do
    if String.contains?(host, @ascii_prefix), do: decode(host), else: host
  end

  def to_unicode(nil), do: nil

  defp ascii?(host), do: Regex.match?(@ascii_only, host)

  defp encode(host) do
    {:ok, host |> String.to_charlist() |> :idna.encode(@idna_options) |> List.to_string()}
  catch
    _kind, _reason -> :error
  end

  defp decode(host) do
    host |> String.to_charlist() |> :idna.decode(@idna_options) |> List.to_string()
  catch
    _kind, _reason -> host
  end
end
