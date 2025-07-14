library(nycflights13)
library(tidyverse)



# 知识点1：学习累加和滚动聚合
x <- 1:10
cumsum(x)
cummean(x)
cummax(x)

flights |> group_by(year, month, day) |>
   summarise(
    mean = mean(dep_delay, na.rm = TRUE)
   ) 


setwd('/mnt/c/Users/Administrator/Desktop')
library(ggsci)
diamonds |> 
   filter(carat < 3 ) |>
   ggplot(
      aes(x = carat,color = cut)
   ) +
   geom_freqpoly(binwidth = 0.1) +
   scale_color_aaas() +
   coord_cartesian(
      xlim = c(0,1) #!重点
   )

diamonds |> 
    ggplot(
      aes(x = x ,y =y )
    ) +
    geom_point(aes(color = "#1E1F1C")) +
    coord_cartesian(ylim = c(2.5,10),
                    xlim = c(3,10)) 
