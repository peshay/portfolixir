defmodule PortfolixirWeb.Risk.PolicyRuleDialog do
  @moduledoc """
  The native dialog that creates, edits and retires a policy rule on
  Wealth → Risk (ADR-0049 §9, pick F1-A, board
  `ux-design-2026-09-23/01-policy-rules-surface`).

  **An edit is a new version** (§4), and the dialog says so before the
  operator saves: "Saving creates version N", with the version in force named
  beside it and the whole version list below — an operator who believes they
  overwrote a cap will not look for its history. The rule's name and context
  are its identity and are not edited here.

  The subject control follows the measure (the §2 matrix): a weight is read
  for a security, a category, cash or a view; a drift for a category or a
  security (the latter with the classification whose plan carries its
  position target); the HHI and the two portfolio metrics for the whole
  basis, the metrics with a window. Thresholds are typed on the measure's own
  scale, and a decimal comma is accepted.

  Retire is a confirmed action; a rule none of whose versions has been in
  force is deleted instead, because nothing was ever measured against it.
  """
  use Phoenix.LiveComponent
  use Gettext, backend: PortfolixirWeb.Gettext

  alias Portfolixir.Actor
  alias Portfolixir.Clock
  alias Portfolixir.Portfolios.PolicyRules
  alias Portfolixir.Portfolios.PolicyRuleVersion
  alias PortfolixirWeb.AppShell
  alias PortfolixirWeb.PolicyRuleLabel
  alias PortfolixirWeb.Risk.PolicyRuleFormat

  @metric_measures ~w(volatility max_drawdown)

  @impl true
  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if changed?(socket, :rule) or not Map.has_key?(socket.assigns, :form) do
        socket
        |> assign(:form, initial_form(socket.assigns[:rule]))
        |> assign(:errors, %{})
        |> assign(:alert, nil)
      else
        socket
      end

    {:ok, socket}
  end

  defp initial_form(nil) do
    %{
      "name" => "",
      "measure" => "weight",
      "subject" => "",
      "classification_id" => "",
      "kind" => "cap",
      "threshold" => "",
      "lower" => "",
      "upper" => "",
      "window" => "365d",
      "severity" => "warn",
      "valid_from" => Date.to_iso8601(Clock.today()),
      "note" => ""
    }
  end

  defp initial_form(rule) do
    version = reference_version(rule)

    %{
      "name" => rule.name,
      "measure" => to_string(version.measure),
      "subject" => subject_value(version),
      "classification_id" =>
        if(version.subject_type == :security and version.classification_id,
          do: to_string(version.classification_id),
          else: ""
        ),
      "kind" => to_string(version.kind),
      "threshold" => decimal_input(version.threshold),
      "lower" => decimal_input(version.lower),
      "upper" => decimal_input(version.upper),
      "window" => (version.window && to_string(version.window)) || "365d",
      "severity" => to_string(version.severity),
      "valid_from" => Date.to_iso8601(Clock.today()),
      "note" => version.note || ""
    }
  end

  # The version the edit starts from: the one in force, else the next one,
  # else the last one the rule had.
  defp reference_version(rule) do
    rule.version_in_force || rule.next_version || List.last(rule.versions)
  end

  defp decimal_input(nil), do: ""

  defp decimal_input(%Decimal{} = value),
    do: value |> Decimal.normalize() |> Decimal.to_string(:normal)

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        subject_options: subject_options(assigns.form["measure"], assigns.options),
        drift_security?: drift_security?(assigns.form),
        band?: assigns.form["kind"] == "band",
        metric?: assigns.form["measure"] in @metric_measures,
        unit: PolicyRuleFormat.unit(assigns.form["measure"])
      )

    ~H"""
    <%!-- Native dialog (UX-DR9, issue 646): opened via showModal() by the
         ModalDialog hook; cancel (Esc) pushes the close event. --%>
    <dialog
      id={@id}
      class="modal policy-rule-dialog"
      phx-hook="ModalDialog"
      data-close-event="close_policy_rule_dialog"
      aria-labelledby={"#{@id}-title"}
    >
      <header class="modal-head">
        <h2 id={"#{@id}-title"}>
          <%= if @rule,
            do: gettext("Change rule — “%{name}”", name: @rule.name),
            else: gettext("New rule") %>
        </h2>
        <button
          type="button"
          class="icon-button"
          aria-label={gettext("Close")}
          phx-click="close_policy_rule_dialog"
        >
          <AppShell.icon name={:x} />
        </button>
      </header>

      <form id="policy-rule-form" phx-change="change" phx-submit="save" phx-target={@myself}>
        <div class="modal-body">
          <p :if={@alert} class="alert-error" role="alert"><%= @alert %></p>
          <p class="hint">
            <%= gettext("Evaluated in the view “%{view}”, on its steerable basis.", view: @view_name) %>
          </p>

          <div class="form-grid">
            <label :if={is_nil(@rule)}>
              <span><%= gettext("Name") %></span>
              <input type="text" name="rule[name]" value={@form["name"]} maxlength="255" required />
              <.field_error errors={@errors} field="name" />
            </label>

            <label>
              <span><%= gettext("Measure") %></span>
              <select name="rule[measure]">
                <option
                  :for={measure <- PolicyRuleVersion.measures()}
                  value={measure}
                  selected={@form["measure"] == measure}
                >
                  <%= PolicyRuleLabel.measure(measure) %>
                </option>
              </select>
              <.field_error errors={@errors} field="measure" />
            </label>

            <label>
              <span><%= gettext("Subject") %></span>
              <select name="rule[subject]">
                <%= for {group, options} <- @subject_options do %>
                  <%= if group do %>
                    <optgroup label={group}>
                      <option :for={{label, value} <- options} value={value} selected={@form["subject"] == value}>
                        <%= label %>
                      </option>
                    </optgroup>
                  <% else %>
                    <option :for={{label, value} <- options} value={value} selected={@form["subject"] == value}>
                      <%= label %>
                    </option>
                  <% end %>
                <% end %>
              </select>
              <.field_error errors={@errors} field="subject" />
            </label>

            <label :if={@drift_security?}>
              <span><%= gettext("Plan of the classification") %></span>
              <select name="rule[classification_id]">
                <option
                  :for={{id, name} <- @options.classifications}
                  value={id}
                  selected={@form["classification_id"] == to_string(id)}
                >
                  <%= name %>
                </option>
              </select>
              <.field_error errors={@errors} field="classification_id" />
            </label>

            <label :if={@metric?}>
              <span><%= gettext("Window") %></span>
              <select name="rule[window]">
                <option
                  :for={window <- PolicyRuleVersion.windows()}
                  value={window}
                  selected={@form["window"] == window}
                >
                  <%= PolicyRuleLabel.window(window) %>
                </option>
              </select>
              <.field_error errors={@errors} field="window" />
            </label>

            <label>
              <span><%= gettext("Kind") %></span>
              <select name="rule[kind]">
                <option :for={kind <- PolicyRuleVersion.kinds()} value={kind} selected={@form["kind"] == kind}>
                  <%= PolicyRuleLabel.kind(kind) %>
                </option>
              </select>
            </label>

            <label :if={not @band?}>
              <span><%= threshold_label(@unit) %></span>
              <input
                type="text"
                inputmode="decimal"
                class="num"
                name="rule[threshold]"
                value={@form["threshold"]}
                autocomplete="off"
              />
              <.field_error errors={@errors} field="threshold" />
            </label>

            <label :if={@band?}>
              <span><%= gettext("From") %> <%= unit_suffix(@unit) %></span>
              <input type="text" inputmode="decimal" class="num" name="rule[lower]" value={@form["lower"]} autocomplete="off" />
              <.field_error errors={@errors} field="lower" />
            </label>

            <label :if={@band?}>
              <span><%= gettext("To") %> <%= unit_suffix(@unit) %></span>
              <input type="text" inputmode="decimal" class="num" name="rule[upper]" value={@form["upper"]} autocomplete="off" />
              <.field_error errors={@errors} field="upper" />
            </label>

            <label>
              <span><%= gettext("Severity") %></span>
              <select name="rule[severity]">
                <option
                  :for={severity <- PolicyRuleVersion.severities()}
                  value={severity}
                  selected={@form["severity"] == severity}
                >
                  <%= PolicyRuleLabel.severity(severity) %>
                </option>
              </select>
            </label>

            <label>
              <span><%= gettext("In force from") %></span>
              <input
                type="text"
                name="rule[valid_from]"
                value={@form["valid_from"]}
                placeholder="YYYY-MM-DD"
                pattern="[0-9]{4}-[0-9]{2}-[0-9]{2}"
                maxlength="10"
                autocomplete="off"
              />
              <.field_error errors={@errors} field="valid_from" />
            </label>

            <label class="form-grid__wide">
              <span><%= gettext("Note (optional)") %></span>
              <input type="text" name="rule[note]" value={@form["note"]} autocomplete="off" />
            </label>
          </div>

          <%= if @rule do %>
            <p class="hint" data-role="policy-rule-version-note">
              <%= version_note(@rule) %>
            </p>
            <details class="perf-table-disclosure" id="policy-rule-versions" open>
              <summary class="disclosure-summary">
                <AppShell.icon name={:chevron_right} size={12} class="disclosure-chevron" />
                <%= gettext("Versions") %>
              </summary>
              <ol class="policy-rule-versions">
                <li :for={{version, index} <- Enum.with_index(@rule.versions, 1)}>
                  <%= gettext("Version %{n}", n: index) %> · <%= PolicyRuleFormat.period(version) %> ·
                  <%= PolicyRuleFormat.line(version) %> · <%= PolicyRuleLabel.severity(version.severity) %>
                </li>
              </ol>
            </details>
          <% end %>

        <div class="modal-footer">
          <%= if @rule do %>
            <%= if never_in_force?(@rule) do %>
              <button
                type="button"
                class="button-ghost"
                phx-click="delete"
                phx-target={@myself}
                data-confirm={gettext("Delete this rule? None of its versions has been in force, so nothing was ever measured against it.")}
              >
                <%= gettext("Delete rule") %>
              </button>
            <% else %>
              <button
                :if={@rule.status != :retired}
                type="button"
                class="button-ghost"
                phx-click="retire"
                phx-target={@myself}
                data-confirm={retire_confirmation(@rule)}
              >
                <%= gettext("Retire rule") %>
              </button>
            <% end %>
          <% end %>
          <span class="modal-footer__spacer"></span>
          <button type="button" class="button-ghost" phx-click="close_policy_rule_dialog">
            <%= gettext("Cancel") %>
          </button>
          <button type="submit" class="button-primary">
            <%= if @rule, do: gettext("Save new version"), else: gettext("Save rule") %>
          </button>
        </div>
        </div>
      </form>
    </dialog>
    """
  end

  attr(:errors, :map, required: true)
  attr(:field, :string, required: true)

  defp field_error(assigns) do
    ~H"""
    <span :if={msg = @errors[@field]} class="field-error"><%= msg %></span>
    """
  end

  defp threshold_label(""), do: gettext("Line")
  defp threshold_label(unit), do: gettext("Line (%{unit})", unit: unit)

  defp unit_suffix(""), do: ""
  defp unit_suffix(unit), do: "(#{unit})"

  # "Saving creates version N", with the version in force named — §4 is
  # invisible otherwise.
  defp version_note(rule) do
    next = length(rule.versions) + 1

    case rule.version_in_force do
      nil ->
        gettext("Saving creates version %{n}. Earlier versions stay readable.", n: next)

      current ->
        index = Enum.find_index(rule.versions, &(&1.id == current.id)) + 1

        if Date.compare(current.valid_from, Clock.today()) == :eq do
          gettext(
            "Saving creates version %{n}. Version %{current} (%{line}) is in force since today and ends tonight — a version that has been the standard stays readable.",
            n: next,
            current: index,
            line: PolicyRuleFormat.line(current)
          )
        else
          gettext(
            "Saving creates version %{n}. Version %{current} (%{line}) is in force since %{from}, ends the day before the new one and stays readable.",
            n: next,
            current: index,
            line: PolicyRuleFormat.line(current),
            from: PortfolixirWeb.Format.date(current.valid_from)
          )
        end
    end
  end

  defp retire_confirmation(rule) do
    if rule.version_in_force &&
         Date.compare(rule.version_in_force.valid_from, Clock.today()) == :eq do
      gettext(
        "Retire this rule? Its version in force started today, so it ends tonight. The rule and its versions stay readable."
      )
    else
      gettext(
        "Retire this rule? It is no longer evaluated from today; the rule and its versions stay readable."
      )
    end
  end

  defp never_in_force?(rule) do
    today = Clock.today()
    not Enum.any?(rule.versions, &PolicyRules.started?(&1, today))
  end

  # -- the subject control ----------------------------------------------------

  defp subject_options(measure, options) do
    allowed =
      PolicyRuleVersion.matrix()
      |> Map.get(measure_atom(measure), [])

    Enum.flat_map(allowed, fn
      :basis ->
        [{nil, [{PolicyRuleLabel.subject_type(:basis), "basis"}]}]

      :cash ->
        [{nil, [{PolicyRuleLabel.subject_type(:cash), "cash"}]}]

      :security ->
        [
          {gettext("Securities"),
           Enum.map(options.securities, fn {id, name} -> {name, "security:#{id}"} end)}
        ]

      :category ->
        Enum.map(options.categories, fn {classification, categories} ->
          {classification,
           Enum.map(categories, fn {cid, id, name} -> {name, "category:#{cid}:#{id}"} end)}
        end)

      :view ->
        [{gettext("Views"), Enum.map(options.views, fn {id, name} -> {name, "view:#{id}"} end)}]
    end)
    |> Enum.reject(fn {_group, entries} -> entries == [] end)
  end

  defp measure_atom(measure) do
    Enum.find(Map.keys(PolicyRuleVersion.matrix()), :weight, &(Atom.to_string(&1) == measure))
  end

  defp subject_value(%{subject_type: :basis}), do: "basis"
  defp subject_value(%{subject_type: :cash}), do: "cash"
  defp subject_value(%{subject_type: :security, security_id: id}), do: "security:#{id}"

  defp subject_value(%{subject_type: :category, classification_id: cid, category_id: id}),
    do: "category:#{cid}:#{id}"

  defp subject_value(%{subject_type: :view, subject_view_id: id}), do: "view:#{id}"

  defp drift_security?(form),
    do: form["measure"] == "drift" and String.starts_with?(form["subject"] || "", "security:")

  # A subject that no longer fits the chosen measure falls back to the first
  # one that does, so the control never submits a pair the matrix refuses.
  defp fit_subject(form, options) do
    values =
      form["measure"]
      |> subject_options(options)
      |> Enum.flat_map(fn {_group, entries} -> Enum.map(entries, &elem(&1, 1)) end)

    cond do
      form["subject"] in values -> form
      values == [] -> Map.put(form, "subject", "")
      true -> Map.put(form, "subject", hd(values))
    end
  end

  defp fit_classification(form, options) do
    ids = Enum.map(options.classifications, &to_string(elem(&1, 0)))

    if drift_security?(form) and form["classification_id"] not in ids,
      do: Map.put(form, "classification_id", List.first(ids) || ""),
      else: form
  end

  # -- events -----------------------------------------------------------------

  @impl true
  def handle_event("change", %{"rule" => params}, socket) do
    form =
      socket.assigns.form
      |> Map.merge(Map.take(params, Map.keys(socket.assigns.form)))
      |> fit_subject(socket.assigns.options)
      |> fit_classification(socket.assigns.options)

    {:noreply, assign(socket, :form, form)}
  end

  def handle_event("save", %{"rule" => params}, socket) do
    form =
      socket.assigns.form
      |> Map.merge(Map.take(params, Map.keys(socket.assigns.form)))
      |> fit_subject(socket.assigns.options)
      |> fit_classification(socket.assigns.options)

    socket = assign(socket, :form, form)
    version = version_attrs(form)

    result =
      case socket.assigns.rule do
        nil ->
          PolicyRules.create_rule(Actor.owner_ui(), %{
            "portfolio_id" => socket.assigns.portfolio_id,
            "view_id" => socket.assigns.view_id,
            "name" => form["name"],
            "version" => version
          })

        rule ->
          PolicyRules.add_version(Actor.owner_ui(), rule, version)
      end

    case result do
      {:ok, _saved} ->
        send(self(), {__MODULE__, {:saved, gettext("Rule saved")}})
        {:noreply, socket}

      {:error, {:version, changeset}} ->
        {:noreply, assign(socket, errors: errors(changeset), alert: nil)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, errors: errors(changeset), alert: nil)}
    end
  end

  def handle_event("retire", _params, socket) do
    case PolicyRules.retire_rule(Actor.owner_ui(), socket.assigns.rule, %{}) do
      {:ok, _closed} ->
        send(self(), {__MODULE__, {:saved, gettext("Rule retired")}})
        {:noreply, socket}

      {:error, :already_retired} ->
        {:noreply, assign(socket, :alert, gettext("This rule is already retired."))}

      {:error, _reason} ->
        {:noreply, assign(socket, :alert, gettext("The rule could not be retired."))}
    end
  end

  def handle_event("delete", _params, socket) do
    case PolicyRules.delete_rule(Actor.owner_ui(), socket.assigns.rule) do
      {:ok, _deleted} ->
        send(self(), {__MODULE__, {:saved, gettext("Rule deleted")}})
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, assign(socket, :alert, gettext("The rule could not be deleted."))}
    end
  end

  # The form's strings as the version's attrs: the subject decoded, a decimal
  # comma read as a point, the fields the kind and measure do not use left out.
  defp version_attrs(form) do
    %{
      "measure" => form["measure"],
      "kind" => form["kind"],
      "severity" => form["severity"],
      "valid_from" => blank_to_nil(form["valid_from"]),
      "note" => blank_to_nil(form["note"])
    }
    |> Map.merge(subject_attrs(form))
    |> Map.merge(threshold_attrs(form))
    |> Map.merge(
      if form["measure"] in @metric_measures, do: %{"window" => form["window"]}, else: %{}
    )
  end

  defp subject_attrs(form) do
    case String.split(form["subject"] || "", ":") do
      ["basis"] ->
        %{"subject_type" => "basis"}

      ["cash"] ->
        %{"subject_type" => "cash"}

      ["view", id] ->
        %{"subject_type" => "view", "subject_view_id" => id}

      ["category", cid, id] ->
        %{"subject_type" => "category", "classification_id" => cid, "category_id" => id}

      ["security", id] ->
        security_attrs(form, id)

      _none ->
        %{}
    end
  end

  defp security_attrs(form, id) do
    base = %{"subject_type" => "security", "security_id" => id}

    if form["measure"] == "drift",
      do: Map.put(base, "classification_id", blank_to_nil(form["classification_id"])),
      else: base
  end

  defp threshold_attrs(%{"kind" => "band"} = form),
    do: %{"lower" => decimal_text(form["lower"]), "upper" => decimal_text(form["upper"])}

  defp threshold_attrs(form), do: %{"threshold" => decimal_text(form["threshold"])}

  defp decimal_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> String.replace(text, ",", ".")
    end
  end

  defp decimal_text(_value), do: nil

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  @subject_fields ~w(subject_type security_id category_id subject_view_id)

  defp errors(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.reduce(%{}, fn {field, [message | _]}, acc ->
      key = to_string(field)
      key = if key in @subject_fields, do: "subject", else: key
      Map.put_new(acc, key, message)
    end)
  end
end
