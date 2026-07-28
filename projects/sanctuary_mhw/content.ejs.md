```{=html}
<% 
// Extract the category name passed from the YAML front matter
const targetCategory = templateParams.selectedCategory;
const filteredItems = items.filter(item => 
  item.categories && item.categories.includes(targetCategory)
);
const newitems = filteredItems.reduce((acc, item) => {
  if (item.id) {
    acc[item.id] = item;
  }
  return acc;
}, {});
%>
```
## <%= targetCategory %>

::: {.details}

```{=html}
<ul>
      <li>
        <%= newitems['c1'].title %>
      </li>
      <li>
        <%= newitems['c2'].title %>
      </li>
</ul>
```

:::
