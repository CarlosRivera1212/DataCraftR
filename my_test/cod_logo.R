library(svgparser)
library(sp)
library(dplyr)
library(ggplot2)
# library(hexSticker)
library(cowplot)
library(showtext)

svg0 = read_svg("test/path0.svg", obj_type = 'data.frame')

ggplot(svg0) +
  aes(x, y, fill = as.factor(elem_idx), group = elem_idx) +
  geom_polygon(alpha = 0.5) +
  coord_equal()

set.seed(123)

n = 600
mn = 0
mx = 500

p1 = data.frame(x = runif(n, mn, mx), y = runif(n, mn, mx))
c1 = filter(svg0, elem_idx == 1)
d1 = point.in.polygon(p1$x, p1$y, c1$x, c1$y)

p2 = data.frame(x = runif(n, mn, mx), y = runif(n, mn, mx))
c2 = filter(svg0, elem_idx == 2)
d2 = point.in.polygon(p2$x, p2$y, c2$x, c2$y)
c3 = filter(svg0, elem_idx == 3)
d3 = point.in.polygon(p2$x, p2$y, c3$x, c3$y)

p4 = data.frame(x = runif(n, mn, mx), y = runif(n, mn, mx))
c4 = filter(svg0, elem_idx == 4)
d4 = point.in.polygon(p4$x, p4$y, c4$x, c4$y)


p_tot = bind_rows(
  mutate(p1, g = 1)[d1 == 1, ],
  mutate(p2, g = 2)[(d2 * !d3) == 1, ],
  mutate(p4, g = 3)[d4 == 1, ]
) %>% 
  mutate(g = as.factor(g))

plt_logo = p_tot %>%
  ggplot() +
  aes(x, y, fill = g) +
  geom_point(
    shape = 21,
    size = 2,
    color = '#333',
    stroke = 0.2
  ) +
  coord_equal() +
  scale_fill_manual(values = c("#00E5FF", "#FF00B8", "#76FF03")) +
  theme_void() +
  theme(legend.position = 'none')

# '#0078f01E'
plt_logo

font_add_google("Bad Script")

fl = c(
  "Bad Script",
  "Charm",
  "Great Vibes",
  "Just Another Hand",
  "Kalam",
  "Kings",
  "Pangolin",
  "Shadows Into Light",
  "Source Sans 3",
  "Twinkle Star"
)

# for(i in fl){
#   print(i)
#   sticker(
#     subplot  = plt_logo,
#     package  = "DataCraftR",
#     s_x      = 1,
#     s_y      = 0.75,
#     s_width = 1,
#     s_height = 1,
#     p_color  = "#0078f0",
#     p_family = i,
#     p_size   = 18,
#     p_y      = 1.35,
#     h_fill   = "#e1effd",
#     h_color  = "#0f0",
#     url      = "pepito",
#     u_color  = "#333",
#     u_size   = 6,
#     filename = paste0("~/Downloads/logo/",i,".png")
#   )
# }


a = (sqrt(3)/2) / 2
b = (a)/tan(60*pi/180)
hex = data.frame(
  x = c(0, a, a, 0, -a, -a),
  y = c(-2*b, -b, b, 2*b, b, -b)
)
# hex = hex*450/a

plt_hex = ggplot()+
  aes(x, y)+
  geom_polygon(data = hex, fill = '#0078f0')+
  geom_polygon(data = hex*0.96, fill = '#e1effd')+
  coord_equal()+
  theme_void()

# plt_hex

plt_point = ggplot(p_tot)+
  aes(x, y, fill = g)+
  geom_point(shape = 21,
             size = 1,
             color = '#333',
             stroke = 0.2)+
  coord_equal()+
  scale_fill_manual(values = c("#00E5FFD2", "#FF00B8D2", "#76FF03D2")) +
  theme_void() +
  theme(legend.position = 'none')

# plt_point


fl = c(
  "Bad Script",
  "Charm",
  "Pangolin",
  "Source Sans 3"
)

for(i in fl){
  # font_add_google(i)
  # showtext_auto()

  plt_logo = ggdraw() +
    draw_plot(plt_hex)+
    draw_plot(plt_point, scale = 0.5, vjust = -0.09)+
    draw_label('DataCraftR', y = 0.3,
               fontfamily = i,
               # fontface = 'bold',
               size = 39, color = '#333')+
    draw_label('github.com/CarlosRivera1212/DataCraftR',
               x = 0.71, y = 0.19,
               fontfamily = 'nanum',
               size = 9, color = '#333', angle = 30)

  plt_logo
  ggsave(paste0(i,'.png'), plt_logo, 'png', 'test/logo/',
         1, 2*sqrt(3)/2, 2, 'in', dpi = 300)
}


# font_add_google('Nanum Gothic Coding', 'namun')
# font_add_google('Nanum Gothic Coding', 'roboto')
# showtext_auto()
plt_logo = ggdraw() +
  draw_plot(plt_hex)+
  draw_plot(plt_point, scale = 0.5, vjust = -0.07)+
  draw_label('DataCraftR', y = 0.29,
             fontfamily = 'Bad Script',
             size = 39, color = '#333')+
  draw_label('github.com/CarlosRivera1212/DataCraftR',
             x = 0.71, y = 0.19,
             fontfamily = 'nanum',
             size = 9, color = '#333', angle = 30)

plt_logo
ggsave('logo.png', plt_logo, 'png', 'test/logo/',
       1, 2*sqrt(3)/2, 2, 'in', dpi = 300)

