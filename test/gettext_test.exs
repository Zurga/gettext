defmodule GettextTest.Translator do
  use Gettext, otp_app: :test_application
end

defmodule GettextTest.TranslatorWithCustomPriv do
  use Gettext, otp_app: :test_application, priv: "translations"
end

defmodule GettextTest.TranslatorWithCustomPluralForms do
  defmodule Plural do
    @behaviour Gettext.Plural
    def nplurals("elv"), do: 2
    def nplurals(other), do: Gettext.Plural.nplurals(other)
    # Opposite of Italian (where 1 is singular, everything else is plural)
    def plural("it", 1), do: 1
    def plural("it", _), do: 0
  end

  use Gettext, otp_app: :test_application, plural_forms: Plural
end

defmodule GettextTest.HandleMissingTranslation do
  use Gettext, otp_app: :test_application

  def handle_missing_translation(locale, domain, msgid, bindings) do
    send(self(), {locale, domain, msgid, bindings})
    super(locale, domain, msgid, bindings)
  end

  def handle_missing_plural_translation(locale, domain, msgid, msgid_plural, n, bindings) do
    send(self(), {locale, domain, msgid, msgid_plural, n, bindings})
    super(locale, domain, msgid, msgid_plural, n, bindings)
  end
end

defmodule GettextTest do
  use ExUnit.Case

  import ExUnit.CaptureLog

  alias GettextTest.Translator
  alias GettextTest.TranslatorWithCustomPriv
  alias GettextTest.TranslatorWithCustomPluralForms
  alias GettextTest.HandleMissingTranslation

  require Translator
  require TranslatorWithCustomPriv

  test "the default locale is \"en\"" do
    assert Gettext.get_locale() == "en"
    assert Gettext.get_locale(Translator) == "en"
  end

  test "get_locale/0,1 and put_locale/1,2: setting/getting the locale" do
    # First, we set the local for just one backend:
    Gettext.put_locale(Translator, "pt_BR")

    # Now, let's check that only that backend was affected.
    assert Gettext.get_locale(Translator) == "pt_BR"
    assert Gettext.get_locale(TranslatorWithCustomPriv) == "en"
    assert Gettext.get_locale() == "en"

    # Now, let's change the global locale:
    Gettext.put_locale("it")

    # Let's check that the global locale was affected and that get_locale/1
    # returns the global locale, but only for backends that have no
    # backend-specific locale set.
    assert Gettext.get_locale() == "it"
    assert Gettext.get_locale(TranslatorWithCustomPriv) == "it"
    assert Gettext.get_locale(Translator) == "pt_BR"
  end

  test "get_locale/0,1: using the default locales" do
    global_default = Application.get_env(:gettext, :default_locale)

    try do
      Application.put_env(:gettext, :default_locale, "fr")
      assert Gettext.get_locale() == "fr"
      assert Gettext.get_locale(Translator) == "fr"
    after
      Application.put_env(:gettext, :default_locale, global_default)
    end
  end

  test "put_locale/2: only accepts binaries" do
    msg = "put_locale/2 only accepts binary locales, got: :en"

    assert_raise ArgumentError, msg, fn ->
      Gettext.put_locale(Translator, :en)
    end
  end

  test "__gettext__(:priv): returns the directory where the translations are stored" do
    assert Translator.__gettext__(:priv) == "priv/gettext"
    assert TranslatorWithCustomPriv.__gettext__(:priv) == "translations"
  end

  test "__gettext__(:otp_app): returns the otp app for the given backend" do
    assert Translator.__gettext__(:otp_app) == :test_application
    assert TranslatorWithCustomPriv.__gettext__(:otp_app) == :test_application
  end

  test "found translations return {:ok, translation}" do
    assert Translator.lgettext("it", "default", nil, "Hello world", %{}) == {:ok, "Ciao mondo"}

    assert Translator.lgettext("it", "errors", nil, "Invalid email address", %{}) ==
             {:ok, "Indirizzo email non valido"}
  end

  test "non-found translations return the argument message" do
    # Unknown msgid.
    assert Translator.lgettext("it", "default", nil, "nonexistent", %{}) ==
             {:default, "nonexistent"}

    # Unknown domain.
    assert Translator.lgettext("it", "unknown", nil, "Hello world", %{}) ==
             {:default, "Hello world"}

    # Unknown locale.
    assert Translator.lgettext("pt_BR", "nonexistent", nil, "Hello world", %{}) ==
             {:default, "Hello world"}
  end

  test "translations with empty msgstrs fallback to {:default, _}" do
    assert Translator.lgettext("it", "default", nil, "Empty msgstr!", %{}) ==
             {:default, "Empty msgstr!"}
  end

  test "a custom 'priv' directory can be used to store translations" do
    assert TranslatorWithCustomPriv.lgettext("it", "default", nil, "Hello world", %{}) ==
             {:ok, "Ciao mondo"}

    assert TranslatorWithCustomPriv.lgettext("it", "errors", nil, "Invalid email address", %{}) ==
             {:ok, "Indirizzo email non valido"}
  end

  test "using a custom Gettext.Plural module" do
    alias TranslatorWithCustomPluralForms, as: T

    assert T.lngettext("it", "default", nil, "One new email", "%{count} new emails", 1, %{}) ==
             {:ok, "1 nuove email"}

    assert T.lngettext("it", "default", nil, "One new email", "%{count} new emails", 2, %{}) ==
             {:ok, "Una nuova email"}
  end

  test "translations can be pluralized" do
    import Translator, only: [lngettext: 7]

    t = lngettext("it", "errors", nil, "There was an error", "There were %{count} errors", 1, %{})
    assert t == {:ok, "C'è stato un errore"}

    t = lngettext("it", "errors", nil, "There was an error", "There were %{count} errors", 3, %{})
    assert t == {:ok, "Ci sono stati 3 errori"}
  end

  test "by default, non-found pluralized translation behave like regular translation" do
    assert Translator.lngettext("it", "not a domain", nil, "foo", "foos", 1, %{}) ==
             {:default, "foo"}

    assert Translator.lngettext("it", "not a domain", nil, "foo", "foos", 10, %{}) ==
             {:default, "foos"}
  end

  test "plural translations with empty msgstrs fallback to {:default, _}" do
    msgid = "Not even one msgstr"
    msgid_plural = "Not even %{count} msgstrs"

    assert Translator.lngettext("it", "default", nil, msgid, msgid_plural, 1, %{}) ==
             {:default, "Not even one msgstr"}

    assert Translator.lngettext("it", "default", nil, msgid, msgid_plural, 2, %{}) ==
             {:default, "Not even 2 msgstrs"}
  end

  test "an error is raised if a plural translation has no plural form for the given locale" do
    log =
      capture_log(fn ->
        Code.eval_quoted(
          quote do
            defmodule BadTranslations do
              use Gettext, otp_app: :test_application, priv: "bad_translations"
            end
          end
        )
      end)

    assert log =~ "translation is missing plural form 2 which is required by the locale \"ru\""

    msgid = "should be at least %{count} character(s)"
    msgid_plural = "should be at least %{count} character(s)"

    assert_raise Gettext.Error,
                 ~r/plural form 2 is required for locale \"ru\" but is missing/,
                 fn ->
                   BadTranslations.lngettext("ru", "errors", nil, msgid, msgid_plural, 8, %{})
                 end
  end

  test "interpolation is supported by lgettext" do
    assert Translator.lgettext("it", "interpolations", nil, "Hello %{name}", %{name: "Jane"}) ==
             {:ok, "Ciao Jane"}

    msgid = "My name is %{name} and I'm %{age}"

    assert Translator.lgettext("it", "interpolations", nil, msgid, %{name: "Meg", age: 33}) ==
             {:ok, "Mi chiamo Meg e ho 33 anni"}

    # A map of bindings is supported as well.
    assert Translator.lgettext("it", "interpolations", nil, "Hello %{name}", %{name: "Jane"}) ==
             {:ok, "Ciao Jane"}
  end

  test "interpolation is supported by lngettext" do
    msgid = "There was an error"
    msgid_plural = "There were %{count} errors"

    assert Translator.lngettext("it", "errors", nil, msgid, msgid_plural, 1, %{}) ==
             {:ok, "C'è stato un errore"}

    assert Translator.lngettext("it", "errors", nil, msgid, msgid_plural, 4, %{}) ==
             {:ok, "Ci sono stati 4 errori"}

    msgid = "You have one message, %{name}"
    msgid_plural = "You have %{count} messages, %{name}"

    assert Translator.lngettext("it", "interpolations", nil, msgid, msgid_plural, 1, %{
             name: "Jane"
           }) ==
             {:ok, "Hai un messaggio, Jane"}

    assert Translator.lngettext("it", "interpolations", nil, msgid, msgid_plural, 0, %{
             name: "Jane"
           }) ==
             {:ok, "Hai 0 messaggi, Jane"}
  end

  test "strings are concatenated before generating function clauses" do
    msgid = "Concatenated and long string"

    assert Translator.lgettext("it", "default", nil, msgid, %{}) ==
             {:ok, "Stringa lunga e concatenata"}

    # assert Translator.lgettext("it", "default", msgid, %{}) ==
    #         {:ok, "Stringa lunga e concatenata"}

    msgid = "A friend"
    msgid_plural = "%{count} friends"

    assert Translator.lngettext("it", "default", nil, msgid, msgid_plural, 1, %{}) ==
             {:ok, "Un amico"}
  end

  test "lgettext/4: default handle_missing_binding preserves key" do
    msgid = "My name is %{name} and I'm %{age}"

    assert Translator.lgettext("it", "interpolations", nil, msgid, %{name: "José"}) ==
             {:missing_bindings, "Mi chiamo José e ho %{age} anni", [:age]}
  end

  test "MissingBindingsError log messages" do
    assert capture_log(fn ->
             Translator.pgettext("test", "Hello %{name}, missing translation!", %{})
           end) =~
             "missing Gettext bindings: [:name] (backend GettextTest.Translator," <>
               " locale \"en\", domain \"default\", msgctxt \"test\", msgid \"Hello " <>
               "%{name}, missing translation!\")"
  end

  test "lgettext/4: interpolation works when a translation is missing" do
    msgid = "Hello %{name}, missing translation!"

    assert Translator.lgettext("pl", "foo", nil, msgid, %{name: "Samantha"}) ==
             {:default, "Hello Samantha, missing translation!"}

    msgid = "Hello world!"
    assert Translator.lgettext("pl", "foo", nil, msgid, %{}) == {:default, "Hello world!"}

    msgid = "Hello %{name}"

    assert Translator.lgettext("pl", "foo", nil, msgid, %{}) ==
             {:missing_bindings, "Hello %{name}", [:name]}
  end

  test "lgettext/4: fallbacks to handle_missing_translation if no translation is found" do
    msgid = "Hello %{name}"
    bindings = %{name: "Jane"}

    assert HandleMissingTranslation.lgettext("pl", "foo", nil, msgid, bindings) ==
             {:default, "Hello Jane"}

    assert_receive {"pl", "foo", ^msgid, ^bindings}
  end

  test "lngettext/6: default handle_missing_binding preserves key" do
    msgid = "You have one message, %{name}"
    msgid_plural = "You have %{count} messages, %{name}"

    assert Translator.lngettext("it", "interpolations", nil, msgid, msgid_plural, 1, %{}) ==
             {:missing_bindings, "Hai un messaggio, %{name}", [:name]}

    assert Translator.lngettext("it", "interpolations", nil, msgid, msgid_plural, 6, %{}) ==
             {:missing_bindings, "Hai 6 messaggi, %{name}", [:name]}
  end

  test "lngettext/6: interpolation works when a translation is missing" do
    msgid = "One error"
    msgid_plural = "%{count} errors"

    assert Translator.lngettext("pl", "foo", nil, msgid, msgid_plural, 1, %{}) ==
             {:default, "One error"}

    assert Translator.lngettext("pl", "foo", nil, msgid, msgid_plural, 9, %{}) ==
             {:default, "9 errors"}
  end

  test "lngettext/6: fallbacks to handle_missing_plural_translation if no translation is found" do
    msgid = "Hello %{name}"
    msgid_plural = "Hello %{name}"
    bindings = %{name: "Jane"}

    assert HandleMissingTranslation.lngettext("pl", "foo", nil, msgid, msgid_plural, 4, bindings) ==
             {:default, "Hello Jane"}

    assert_receive {"pl", "foo", ^msgid, ^msgid_plural, 4, ^bindings}
  end

  test "dgettext/3: binary msgid at compile-time" do
    Gettext.put_locale(Translator, "it")

    assert Translator.dgettext("errors", "Invalid email address") == "Indirizzo email non valido"
    keys = %{name: "Jim"}
    assert Translator.dgettext("interpolations", "Hello %{name}", keys) == "Ciao Jim"

    log =
      capture_log(fn ->
        assert Translator.dgettext("interpolations", "Hello %{name}") == "Ciao %{name}"
      end)

    assert log =~ ~s/[error] missing Gettext bindings: [:name]/
  end

  # Macros.

  @gettext_msgid "Hello world"

  test "gettext/2: binary-ish msgid at compile-time" do
    Gettext.put_locale(Translator, "it")
    assert Translator.gettext("Hello world") == "Ciao mondo"
    assert Translator.gettext(@gettext_msgid) == "Ciao mondo"
    assert Translator.gettext(~s(Hello world)) == "Ciao mondo"
  end

  test "pgettext/3: test with context based translations" do
    Gettext.put_locale(Translator, "it")
    assert Translator.pgettext("test", @gettext_msgid) == "Ciao mondo"
    assert Translator.pgettext("test", ~s(Hello world)) == "Ciao mondo"
    assert Translator.pgettext("test", "Hello world", %{}) == "Ciao mondo"
    assert Translator.pgettext("test", "Hello %{name}", %{name: "Marco"}) == "Ciao Marco"
    # Missing translation
    assert Translator.pgettext("test", "Hello missing", %{}) == "Hello missing"
  end

  test "pgettext/3, pngettext/4: dynamic context raises" do
    code =
      quote do
        require Translator
        context = "test"
        Translator.pgettext(context, "Hello world")
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:context"
    assert message =~ "Gettext.gettext(GettextTest.Translator, string)"

    code =
      quote do
        require Translator
        context = "test"
        Translator.pngettext(context, "Hello world", "Hello world", 5)
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:context"
    assert message =~ "Gettext.gettext(GettextTest.Translator, string)"
  end

  test "dpgettext/4, dpngettext/5: dynamic context or dynamic domain raises" do
    code =
      quote do
        require Translator
        context = "test"
        Translator.dpgettext("default", context, "Hello world")
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:context"
    assert message =~ "Gettext.gettext(GettextTest.Translator, string)"

    code =
      quote do
        require Translator
        domain = "test"
        Translator.dpgettext(domain, "test", "Hello world")
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:domain"
    assert message =~ "Gettext.gettext(GettextTest.Translator, string)"

    code =
      quote do
        require Translator
        context = "test"
        Translator.dpngettext("default", context, "Hello world", "Hello world", n)
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:context"
    assert message =~ "Gettext.gettext(GettextTest.Translator, string)"

    code =
      quote do
        require Translator
        domain = "test"
        Translator.dpngettext(domain, "test", "Hello world", "Hello World", n)
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:domain"
    assert message =~ "Gettext.gettext(GettextTest.Translator, string)"
  end

  test "dpgettext/4: context and domain based translations" do
    Gettext.put_locale(Translator, "it")
    assert Translator.dpgettext("default", "test", "Hello world", %{}) == "Ciao mondo"
  end

  test "dgettext/3 and dngettext/2: non-binary things at compile-time" do
    code =
      quote do
        require Translator
        msgid = "Invalid email address"
        Translator.dgettext("errors", msgid)
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:msgid"
    assert message =~ "Gettext.gettext(GettextTest.Translator, string)"

    code =
      quote do
        require Translator
        msgid_plural = ~s(foo #{1 + 1} bar)
        Translator.dngettext("default", "foo", msgid_plural, 1)
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:msgid_plural"
    assert message =~ "Gettext.gettext(GettextTest.Translator, string)"

    code =
      quote do
        require Translator
        domain = "dynamic_domain"
        Translator.dgettext(domain, "hello")
      end

    error = assert_raise ArgumentError, fn -> Code.eval_quoted(code) end
    message = ArgumentError.message(error)
    assert message =~ "Gettext macros expect translation keys"
    assert message =~ "{:domain"
  end

  test "dngettext/5" do
    Gettext.put_locale(Translator, "it")

    assert Translator.dngettext(
             "interpolations",
             "You have one message, %{name}",
             "You have %{count} messages, %{name}",
             1,
             %{name: "James"}
           ) == "Hai un messaggio, James"

    assert Translator.dngettext(
             "interpolations",
             "You have one message, %{name}",
             "You have %{count} messages, %{name}",
             2,
             %{name: "James"}
           ) == "Hai 2 messaggi, James"
  end

  @ngettext_msgid "One new email"
  @ngettext_msgid_plural "%{count} new emails"

  test "ngettext/4" do
    Gettext.put_locale(Translator, "it")
    assert Translator.ngettext("One new email", "%{count} new emails", 1) == "Una nuova email"
    assert Translator.ngettext("One new email", "%{count} new emails", 2) == "2 nuove email"

    assert Translator.ngettext(@ngettext_msgid, @ngettext_msgid_plural, 1) == "Una nuova email"
    assert Translator.ngettext(@ngettext_msgid, @ngettext_msgid_plural, 2) == "2 nuove email"
  end

  test "pngettext/4" do
    Gettext.put_locale(Translator, "it")

    assert Translator.pngettext("test", "One new email", "%{count} new emails", 1) ==
             "Una nuova test email"

    assert Translator.pngettext("test", "One new email", "%{count} new emails", 2) ==
             "2 nuove test email"

    assert Translator.pngettext("test", @ngettext_msgid, @ngettext_msgid_plural, 1) ==
             "Una nuova test email"

    assert Translator.pngettext("test", @ngettext_msgid, @ngettext_msgid_plural, 2) ==
             "2 nuove test email"
  end

  test "the d?n?gettext macros support a kw list for interpolation" do
    Gettext.put_locale(Translator, "it")
    assert Translator.gettext("%{msg}", msg: "foo") == "foo"
  end

  test "(d)(p)gettext_noop" do
    assert Translator.dpgettext_noop("errors", "test", "Oops") == {"Oops", "test"}
    assert Translator.dgettext_noop("errors", "Oops") == {"Oops", nil}
    assert Translator.gettext_noop("Hello %{name}!") == {"Hello %{name}!", nil}
  end

  test "(d)(p)ngettext_noop" do
    assert Translator.dpngettext_noop("errors", "test", "One error", "%{count} errors") ==
             {"One error", "%{count} errors", "test"}

    assert Translator.dngettext_noop("errors", "One error", "%{count} errors") ==
             {"One error", "%{count} errors", nil}

    assert Translator.ngettext_noop("One message", "%{count} messages") ==
             {"One message", "%{count} messages", nil}

    assert Translator.pngettext_noop("test", "One message", "%{count} messages") ==
             {"One message", "%{count} messages", "test"}
  end

  # Actual Gettext functions (not the ones generated in the modules that `use
  # Gettext`).

  test "dgettext/4" do
    Gettext.put_locale(Translator, "it")

    msgid = "Invalid email address"
    assert Gettext.dgettext(Translator, "errors", msgid) == "Indirizzo email non valido"

    assert Gettext.dgettext(Translator, "foo", "Foo") == "Foo"

    log =
      capture_log(fn ->
        assert Gettext.dgettext(Translator, "interpolations", "Hello %{name}", %{}) ==
                 "Ciao %{name}"
      end)

    assert log =~ "[error] missing Gettext bindings: [:name]"
  end

  test "gettext/3" do
    Gettext.put_locale(Translator, "it")
    assert Gettext.gettext(Translator, "Hello world") == "Ciao mondo"
    assert Gettext.gettext(Translator, "Nonexistent") == "Nonexistent"
  end

  test "pgettext/3" do
    Gettext.put_locale(Translator, "it")
    assert Gettext.pgettext(Translator, "test", "Hello world") == "Ciao mondo"
    assert Gettext.pgettext(Translator, "test", "Nonexistent") == "Nonexistent"
  end

  test "dngettext/6" do
    Gettext.put_locale(Translator, "it")
    msgid = "You have one message, %{name}"
    msgid_plural = "You have %{count} messages, %{name}"

    assert Gettext.dngettext(Translator, "interpolations", msgid, msgid_plural, 1, %{name: "Meg"}) ==
             "Hai un messaggio, Meg"

    assert Gettext.dngettext(Translator, "interpolations", msgid, msgid_plural, 5, %{name: "Meg"}) ==
             "Hai 5 messaggi, Meg"
  end

  test "dpngettext/6" do
    Gettext.put_locale(Translator, "it")
    msgid = "You have one message, %{name}"
    msgid_plural = "You have %{count} messages, %{name}"

    assert Gettext.dpngettext(Translator, "interpolations", "test", msgid, msgid_plural, 1, %{
             name: "Meg"
           }) ==
             "Hai un messaggio, Meg"

    assert Gettext.dpngettext(Translator, "interpolations", "test", msgid, msgid_plural, 5, %{
             name: "Meg"
           }) ==
             "Hai 5 messaggi, Meg"

    assert Gettext.dpngettext(
             Translator,
             "default",
             "test",
             "One new email",
             "%{count} new emails",
             5,
             %{name: "Meg"}
           ) == "5 nuove test email"
  end

  test "pngettext/6" do
    Gettext.put_locale(Translator, "it")
    msgctxt = "test"
    msgid = "One cake, %{name}"
    msgid_plural = "%{count} cakes, %{name}"

    assert Gettext.pngettext(Translator, msgctxt, msgid, msgid_plural, 1, %{name: "Meg"}) ==
             "One cake, Meg"

    assert Gettext.pngettext(Translator, msgctxt, msgid, msgid_plural, 5, %{name: "Meg"}) ==
             "5 cakes, Meg"
  end

  test "ngettext/5" do
    Gettext.put_locale(Translator, "it")
    msgid = "One cake, %{name}"
    msgid_plural = "%{count} cakes, %{name}"
    assert Gettext.ngettext(Translator, msgid, msgid_plural, 1, %{name: "Meg"}) == "One cake, Meg"
    assert Gettext.ngettext(Translator, msgid, msgid_plural, 5, %{name: "Meg"}) == "5 cakes, Meg"
  end

  test "the d?n?gettext functions support kw list for interpolations" do
    Gettext.put_locale(Translator, "it")
    assert Gettext.gettext(Translator, "Hello %{name}", name: "José") == "Hello José"
  end

  test "with_locale/3 runs a function with a given locale and returns the returned value" do
    Gettext.put_locale(Translator, "fr")
    # no 'fr' translation
    assert Gettext.gettext(Translator, "Hello world") == "Hello world"

    res =
      Gettext.with_locale(Translator, "it", fn ->
        assert Gettext.gettext(Translator, "Hello world") == "Ciao mondo"
        :foo
      end)

    assert Gettext.get_locale(Translator) == "fr"
    assert res == :foo
  end

  test "with_locale/3 resets the locale even if the given function raises" do
    Gettext.put_locale(Translator, "fr")

    assert_raise RuntimeError, fn ->
      Gettext.with_locale(Translator, "it", fn -> raise "foo" end)
    end

    assert Gettext.get_locale(Translator) == "fr"

    catch_throw(Gettext.with_locale(Translator, "it", fn -> throw(:foo) end))
    assert Gettext.get_locale(Translator) == "fr"
  end

  test "with_locale/3: doesn't raise if no locale was set (defaulting to 'en')" do
    Process.delete(Translator)

    Gettext.with_locale(Translator, "it", fn ->
      assert Gettext.gettext(Translator, "Hello world") == "Ciao mondo"
    end)

    assert Gettext.get_locale(Translator) == "en"
  end

  test "known_locales/1: returns all the locales for which a backend has PO files" do
    assert Gettext.known_locales(Translator) == ["it"]
    assert Gettext.known_locales(TranslatorWithCustomPriv) == ["it"]
  end

  test "a warning is issued in l(n)gettext when the domain contains slashes" do
    log =
      capture_log(fn ->
        assert Translator.dgettext("sub/dir/domain", "hello") == "hello"
      end)

    assert log =~ ~s(Slashes in domains are not supported: "sub/dir/domain")
  end

  if function_exported?(Kernel.ParallelCompiler, :async, 1) do
    defmodule TranslatorWithOneModulePerLocale do
      use Gettext, otp_app: :test_application, one_module_per_locale: true
    end

    test "may define one module per locale" do
      import TranslatorWithOneModulePerLocale, only: [lgettext: 5, lngettext: 7]
      assert Code.ensure_loaded?(TranslatorWithOneModulePerLocale.T_it)

      # Found on default domain.
      assert lgettext("it", "default", nil, "Hello world", %{}) == {:ok, "Ciao mondo"}

      # Found on errors domain.
      assert lgettext("it", "errors", nil, "Invalid email address", %{}) ==
               {:ok, "Indirizzo email non valido"}

      # Found with plural form.
      assert lngettext(
               "it",
               "errors",
               nil,
               "There was an error",
               "There were %{count} errors",
               1,
               %{}
             ) ==
               {:ok, "C'è stato un errore"}

      # Unknown msgid.
      assert lgettext("it", "default", nil, "nonexistent", %{}) == {:default, "nonexistent"}

      # Unknown domain.
      assert lgettext("it", "unknown", nil, "Hello world", %{}) == {:default, "Hello world"}

      # Unknown locale.
      assert lgettext("pt_BR", "nonexistent", nil, "Hello world", %{}) ==
               {:default, "Hello world"}
    end
  end
end
