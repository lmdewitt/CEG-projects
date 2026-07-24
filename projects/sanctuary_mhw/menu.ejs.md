
```{=html}
<div class="custom-card-container list">
<% for (const tile of items) { %>
  <div style="width=150px; class="custom-card text-center border-0" <%= metadataAttrs(tile) %>>
    <a href="<%- tile.href %>">
      <img src="<%- tile.image %>" alt="<%= tile.title %>  style="height=150px; object-fit: cover;" class="card-img"/>
    </a>
    <h6 class="card-title" style="margin-top:.5rem;"><%= tile.title %></h6>
  </div>
<% } %>

</div>

```