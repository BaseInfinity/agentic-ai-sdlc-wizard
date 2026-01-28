package main

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

type Item struct {
	ID    int     `json:"id"`
	Name  string  `json:"name"`
	Price float64 `json:"price"`
}

var items = []Item{
	{ID: 1, Name: "Item 1", Price: 10.0},
	{ID: 2, Name: "Item 2", Price: 20.0},
}

func main() {
	r := SetupRouter()
	r.Run(":8080")
}

func SetupRouter() *gin.Engine {
	r := gin.Default()

	r.GET("/health", healthCheck)
	r.GET("/items", getItems)
	r.GET("/items/:id", getItem)
	r.POST("/items", createItem)

	return r
}

func healthCheck(c *gin.Context) {
	c.JSON(http.StatusOK, gin.H{"status": "ok"})
}

func getItems(c *gin.Context) {
	c.JSON(http.StatusOK, items)
}

func getItem(c *gin.Context) {
	id := c.Param("id")
	for _, item := range items {
		if string(rune(item.ID+'0')) == id {
			c.JSON(http.StatusOK, item)
			return
		}
	}
	c.JSON(http.StatusNotFound, gin.H{"error": "not found"})
}

func createItem(c *gin.Context) {
	var item Item
	if err := c.ShouldBindJSON(&item); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	item.ID = len(items) + 1
	items = append(items, item)
	c.JSON(http.StatusCreated, item)
}
